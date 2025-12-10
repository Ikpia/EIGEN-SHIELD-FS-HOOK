// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/// @notice EigenShield Flow Sentinel hook.
/// Guards swaps by requiring a 67% (configurable) quorum of operator attestations.
contract EigenShieldHook is BaseHook, EIP712 {
    using PoolIdLibrary for PoolKey;

    uint16 internal constant BPS = 10_000;

    address public immutable guardian;
    uint16 public quorumBps; // e.g. 6700 = 67%
    uint8 public minConfidence; // 0-100
    uint32 public freshnessWindow; // seconds

    mapping(address => bool) public isOperator;
    uint256 public operatorCount;

    struct Attestation {
        address operator;
        bool isSafe;
        uint8 confidence;
        uint64 timestamp;
        bytes signature;
    }

    struct AttestationBundle {
        bytes32 intentId;
        Attestation[] attestations;
    }

    struct QuorumResult {
        uint256 safeVotes;
        uint256 maliciousVotes;
        uint256 uniqueOperators;
        bool safeQuorumReached;
        bool maliciousQuorumReached;
    }

    event SwapChecked(
        PoolId indexed poolId,
        bytes32 indexed intentId,
        uint256 safeVotes,
        uint256 maliciousVotes,
        uint256 operatorCount,
        bool passed
    );

    error NotGuardian();
    error InvalidQuorum();
    error IntentIdMismatch();
    error NoOperatorsConfigured();
    error OperatorNotAuthorized(address signer);
    error DuplicateAttestation(address signer);
    error StaleAttestation(address signer);
    error ConfidenceTooLow(address signer, uint8 confidence);
    error MaliciousQuorum();
    error SafeQuorumNotMet();

    bytes32 private constant INTENT_TYPEHASH =
        keccak256("Intent(bytes32 poolId,address trader,bool zeroForOne,int256 amountSpecified,uint160 sqrtPriceLimitX96)");
    bytes32 private constant ATTESTATION_TYPEHASH =
        keccak256(
            "Attestation(bytes32 intentId,address operator,bool isSafe,uint8 confidence,uint64 timestamp,bytes32 poolId,bool zeroForOne,int256 amountSpecified,uint160 sqrtPriceLimitX96)"
        );

    constructor(
        IPoolManager _poolManager,
        address[] memory operators,
        uint16 quorumBps_,
        uint8 minConfidence_,
        uint32 freshnessWindow_
    ) BaseHook(_poolManager) EIP712("EigenShieldHook", "1") {
        if (quorumBps_ == 0 || quorumBps_ > BPS) revert InvalidQuorum();
        guardian = msg.sender;
        quorumBps = quorumBps_;
        minConfidence = minConfidence_;
        freshnessWindow = freshnessWindow_;
        _setOperators(operators, true);
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian();
        _;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function updateQuorum(uint16 newQuorumBps) external onlyGuardian {
        if (newQuorumBps == 0 || newQuorumBps > BPS) revert InvalidQuorum();
        quorumBps = newQuorumBps;
    }

    function updateMinConfidence(uint8 newMinConfidence) external onlyGuardian {
        minConfidence = newMinConfidence;
    }

    function updateFreshnessWindow(uint32 newWindow) external onlyGuardian {
        freshnessWindow = newWindow;
    }

    function setOperators(address[] calldata operators, bool active) external onlyGuardian {
        _setOperators(operators, active);
    }

    /// @notice Deterministic swap intent hash that operators sign.
    function computeIntentId(PoolKey calldata key, SwapParams calldata params, address trader)
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                INTENT_TYPEHASH, key.toId(), trader, params.zeroForOne, params.amountSpecified, params.sqrtPriceLimitX96
            )
        );
    }

    /// @notice Hash to sign for an attestation (EIP-712).
    function hashAttestation(
        Attestation calldata attestation,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes32 intentId
    ) external view returns (bytes32) {
        return _attestationDigest(attestation, key, params, intentId);
    }

    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (operatorCount == 0) revert NoOperatorsConfigured();

        AttestationBundle memory bundle = abi.decode(hookData, (AttestationBundle));
        bytes32 expectedIntent = computeIntentId(key, params, sender);

        if (bundle.intentId != expectedIntent) revert IntentIdMismatch();

        QuorumResult memory result = _verify(bundle.attestations, key, params, expectedIntent);

        if (result.maliciousQuorumReached) revert MaliciousQuorum();
        if (!result.safeQuorumReached) revert SafeQuorumNotMet();

        emit SwapChecked(key.toId(), bundle.intentId, result.safeVotes, result.maliciousVotes, operatorCount, true);

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _verify(
        Attestation[] memory attestations,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes32 intentId
    ) internal view returns (QuorumResult memory result) {
        if (attestations.length == 0) revert SafeQuorumNotMet();

        uint256 totalOperators = operatorCount;
        bool[] memory used = new bool[](attestations.length);
        // track seen signers via mapping in memory to prevent duplicates
        // Using hashing to packed array key; cheaper approach is mapping but not possible in memory, so use storage slot free approach.
        // We expect small attestation sets in practice (<50) so nested loop is acceptable here.

        for (uint256 i = 0; i < attestations.length; i++) {
            Attestation memory att = attestations[i];

            if (!isOperator[att.operator]) revert OperatorNotAuthorized(att.operator);
            if (att.confidence < minConfidence) revert ConfidenceTooLow(att.operator, att.confidence);
            if (block.timestamp > att.timestamp + freshnessWindow) revert StaleAttestation(att.operator);

            // Prevent duplicate operators
            for (uint256 j = 0; j < i; j++) {
                if (!used[j]) continue;
                if (attestations[j].operator == att.operator) revert DuplicateAttestation(att.operator);
            }
            used[i] = true;

            bytes32 digest = _attestationDigest(att, key, params, intentId);
            address signer = ECDSA.recover(digest, att.signature);
            if (signer != att.operator) revert OperatorNotAuthorized(signer);

            if (att.isSafe) {
                result.safeVotes++;
            } else {
                result.maliciousVotes++;
            }
        }

        result.uniqueOperators = result.safeVotes + result.maliciousVotes;

        result.safeQuorumReached = (result.safeVotes * BPS) >= quorumBps * totalOperators;
        result.maliciousQuorumReached = (result.maliciousVotes * BPS) >= quorumBps * totalOperators;
    }

    function _attestationDigest(
        Attestation memory attestation,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes32 intentId
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                ATTESTATION_TYPEHASH,
                intentId,
                attestation.operator,
                attestation.isSafe,
                attestation.confidence,
                attestation.timestamp,
                key.toId(),
                params.zeroForOne,
                params.amountSpecified,
                params.sqrtPriceLimitX96
            )
        );
        return _hashTypedDataV4(structHash);
    }

    function _setOperators(address[] memory operators, bool active) internal {
        uint256 len = operators.length;
        for (uint256 i = 0; i < len; i++) {
            address op = operators[i];
            if (op == address(0)) continue;

            bool currentlyActive = isOperator[op];
            if (currentlyActive == active) continue;

            isOperator[op] = active;
            operatorCount = active ? operatorCount + 1 : operatorCount - 1;
        }
    }
}

