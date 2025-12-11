// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, StdInvariant} from "forge-std/Test.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {EigenShieldHook} from "../src/EigenShieldHook.sol";
import {BaseTest} from "./utils/BaseTest.sol";

/// @notice Extended suite covering 100+ scenarios without altering the main hook contract.
contract EigenShieldHookMatrixTest is BaseTest {
    using PoolIdLibrary for PoolKey;

    EigenShieldHook internal hook;
    PoolKey internal poolKey;
    SwapParams internal swapParams;
    address internal trader;

    uint256 internal opKeyA = 0xA11CE;
    uint256 internal opKeyB = 0xB0B;
    uint256 internal opKeyC = 0xC0DE;

    function setUp() public {
        vm.warp(1_700_000_000);
        deployArtifactsAndLabel();
        _bootstrapHook(uint16(6700), uint8(60), uint32(300));
    }

    function _bootstrapHook(uint16 quorumBps, uint8 minConfidence, uint32 freshnessWindow) internal {
        (Currency currency0, Currency currency1) = deployCurrencyPair();
        // suppress unused warnings
        currency0; currency1;
        trader = makeAddr("trader-matrix");

        address flags = address(uint160(Hooks.BEFORE_SWAP_FLAG) ^ (0xABCD << 144));

        address[] memory operators = new address[](3);
        operators[0] = vm.addr(opKeyA);
        operators[1] = vm.addr(opKeyB);
        operators[2] = vm.addr(opKeyC);

        bytes memory constructorArgs =
            abi.encode(poolManager, operators, quorumBps, minConfidence, freshnessWindow);
        deployCodeTo("EigenShieldHook.sol:EigenShieldHook", constructorArgs, flags);
        hook = EigenShieldHook(flags);

        poolKey = PoolKey(Currency.wrap(address(1)), Currency.wrap(address(2)), 3000, 60, IHooks(hook));
        swapParams =
            SwapParams({zeroForOne: true, amountSpecified: -int256(1e18), sqrtPriceLimitX96: uint160(4_295_128_740)});
    }

    function _att(uint256 pk, bool isSafe, uint8 confidence, uint64 timestamp, bytes32 intentId)
        internal
        view
        returns (EigenShieldHook.Attestation memory att)
    {
        att = EigenShieldHook.Attestation({
            operator: vm.addr(pk),
            isSafe: isSafe,
            confidence: confidence,
            timestamp: timestamp,
            signature: ""
        });
        bytes32 digest = hook.hashAttestation(att, poolKey, swapParams, intentId);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        att.signature = abi.encodePacked(r, s, v);
    }

    /// @notice Runs 100 matrix scenarios across quorum, stale, confidence, duplicates, and malicious patterns.
    function testMatrixOf100Scenarios() public {
        bytes32 intentId = hook.computeIntentId(poolKey, swapParams, trader);
        uint256 executed;

        for (uint256 i = 0; i < 100; i++) {
            uint256 mode = i % 5;
            EigenShieldHook.Attestation[] memory atts;

            if (mode == 0) {
                // Stale attestation should revert
                atts = new EigenShieldHook.Attestation[](3);
                atts[0] = _att(opKeyA, true, 90, uint64(block.timestamp - hook.freshnessWindow() - 1), intentId);
                atts[1] = _att(opKeyB, true, 90, uint64(block.timestamp), intentId);
                atts[2] = _att(opKeyC, true, 90, uint64(block.timestamp), intentId);
                vm.expectRevert(abi.encodeWithSelector(EigenShieldHook.StaleAttestation.selector, vm.addr(opKeyA)));
            } else if (mode == 1) {
                // Malicious quorum reached should revert
                atts = new EigenShieldHook.Attestation[](3);
                atts[0] = _att(opKeyA, false, 90, uint64(block.timestamp), intentId);
                atts[1] = _att(opKeyB, false, 90, uint64(block.timestamp), intentId);
                atts[2] = _att(opKeyC, false, 90, uint64(block.timestamp), intentId);
                vm.expectRevert(EigenShieldHook.MaliciousQuorum.selector);
            } else if (mode == 2) {
                // Insufficient safe quorum should revert
                atts = new EigenShieldHook.Attestation[](1);
                atts[0] = _att(opKeyA, true, 90, uint64(block.timestamp), intentId);
                vm.expectRevert(EigenShieldHook.SafeQuorumNotMet.selector);
            } else if (mode == 3) {
                // Duplicate operator should revert
                atts = new EigenShieldHook.Attestation[](2);
                EigenShieldHook.Attestation memory base =
                    _att(opKeyA, true, 90, uint64(block.timestamp), intentId);
                atts[0] = base;
                atts[1] = base;
                vm.expectRevert(abi.encodeWithSelector(EigenShieldHook.DuplicateAttestation.selector, vm.addr(opKeyA)));
            } else {
                // Happy path: all safe, valid quorum
                atts = new EigenShieldHook.Attestation[](3);
                atts[0] = _att(opKeyA, true, 90, uint64(block.timestamp), intentId);
                atts[1] = _att(opKeyB, true, 90, uint64(block.timestamp), intentId);
                atts[2] = _att(opKeyC, true, 90, uint64(block.timestamp), intentId);
            }

            bytes memory hookData =
                abi.encode(EigenShieldHook.AttestationBundle({intentId: intentId, attestations: atts}));

            vm.prank(address(poolManager));
            if (mode == 4) {
                (bytes4 selector,,) = hook.beforeSwap(trader, poolKey, swapParams, hookData);
                assertEq(selector, hook.beforeSwap.selector);
            } else {
                hook.beforeSwap(trader, poolKey, swapParams, hookData);
            }
            executed++;
        }

        assertEq(executed, 100, "ran 100 scenarios");
    }

    /// @notice Checks boundary quorum values at exact threshold.
    function testQuorumBoundaryAtThreshold() public {
        hook.updateQuorum(6666); // minimum to allow 2/3 safe votes to pass
        bytes32 intentId = hook.computeIntentId(poolKey, swapParams, trader);
        EigenShieldHook.Attestation[] memory atts = new EigenShieldHook.Attestation[](3);
        atts[0] = _att(opKeyA, true, 90, uint64(block.timestamp), intentId);
        atts[1] = _att(opKeyB, true, 90, uint64(block.timestamp), intentId);
        atts[2] = _att(opKeyC, false, 90, uint64(block.timestamp), intentId);

        bytes memory hookData =
            abi.encode(EigenShieldHook.AttestationBundle({intentId: intentId, attestations: atts}));

        vm.prank(address(poolManager));
        (bytes4 selector,,) = hook.beforeSwap(trader, poolKey, swapParams, hookData);
        assertEq(selector, hook.beforeSwap.selector);
    }

    /// @notice Ensures low confidence votes revert.
    function testLowConfidenceReverts() public {
        bytes32 intentId = hook.computeIntentId(poolKey, swapParams, trader);
        EigenShieldHook.Attestation[] memory atts = new EigenShieldHook.Attestation[](3);
        atts[0] = _att(opKeyA, true, hook.minConfidence() - 1, uint64(block.timestamp), intentId);
        atts[1] = _att(opKeyB, true, hook.minConfidence(), uint64(block.timestamp), intentId);
        atts[2] = _att(opKeyC, true, hook.minConfidence(), uint64(block.timestamp), intentId);

        bytes memory hookData =
            abi.encode(EigenShieldHook.AttestationBundle({intentId: intentId, attestations: atts}));

        vm.expectRevert(abi.encodeWithSelector(EigenShieldHook.ConfidenceTooLow.selector, vm.addr(opKeyA), hook.minConfidence() - 1));
        vm.prank(address(poolManager));
        hook.beforeSwap(trader, poolKey, swapParams, hookData);
    }

    /// @notice Ensures intentId mismatch reverts.
    function testIntentIdMismatchReverts() public {
        bytes32 correctIntent = hook.computeIntentId(poolKey, swapParams, trader);
        bytes32 wrongIntent = bytes32(uint256(correctIntent) ^ uint256(1));
        EigenShieldHook.Attestation[] memory atts = new EigenShieldHook.Attestation[](3);
        atts[0] = _att(opKeyA, true, 90, uint64(block.timestamp), wrongIntent);
        atts[1] = _att(opKeyB, true, 90, uint64(block.timestamp), wrongIntent);
        atts[2] = _att(opKeyC, true, 90, uint64(block.timestamp), wrongIntent);

        bytes memory hookData =
            abi.encode(EigenShieldHook.AttestationBundle({intentId: wrongIntent, attestations: atts}));

        vm.expectRevert(EigenShieldHook.IntentIdMismatch.selector);
        vm.prank(address(poolManager));
        hook.beforeSwap(trader, poolKey, swapParams, hookData);
    }

    /// @notice Ensures unauthorized operator signatures are rejected.
    function testOperatorNotAuthorizedReverts() public {
        bytes32 intentId = hook.computeIntentId(poolKey, swapParams, trader);
        EigenShieldHook.Attestation[] memory atts = new EigenShieldHook.Attestation[](1);

        // craft attestation signed by unknown key
        uint256 roguePk = 0xBAD5EED;
        atts[0] = _att(roguePk, true, 90, uint64(block.timestamp), intentId);

        bytes memory hookData =
            abi.encode(EigenShieldHook.AttestationBundle({intentId: intentId, attestations: atts}));

        vm.expectRevert(abi.encodeWithSelector(EigenShieldHook.OperatorNotAuthorized.selector, vm.addr(roguePk)));
        vm.prank(address(poolManager));
        hook.beforeSwap(trader, poolKey, swapParams, hookData);
    }

    /// @notice Ensures guardian-only setters enforce access control.
    function testGuardianOnlySetters() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(EigenShieldHook.NotGuardian.selector);
        hook.updateQuorum(7000);

        vm.prank(address(0xBEEF));
        vm.expectRevert(EigenShieldHook.NotGuardian.selector);
        hook.updateMinConfidence(99);

        vm.prank(address(0xBEEF));
        vm.expectRevert(EigenShieldHook.NotGuardian.selector);
        hook.updateFreshnessWindow(10);
    }

    /// @notice Allows guardian to update parameters and keeps operator count intact.
    function testGuardianUpdatesParameters() public {
        uint16 newQuorum = 7500;
        uint8 newMinConf = 80;
        uint32 newWindow = 600;

        hook.updateQuorum(newQuorum);
        hook.updateMinConfidence(newMinConf);
        hook.updateFreshnessWindow(newWindow);

        assertEq(hook.quorumBps(), newQuorum);
        assertEq(hook.minConfidence(), newMinConf);
        assertEq(hook.freshnessWindow(), newWindow);
        assertEq(hook.operatorCount(), 3);
    }

    /// @notice Ensures operator toggling preserves accurate counts.
    function testSetOperatorsTogglesCounts() public {
        address[] memory ops = new address[](1);
        ops[0] = vm.addr(opKeyA);
        hook.setOperators(ops, false);
        assertEq(hook.operatorCount(), 2);
        assertFalse(hook.isOperator(vm.addr(opKeyA)));

        hook.setOperators(ops, true);
        assertEq(hook.operatorCount(), 3);
        assertTrue(hook.isOperator(vm.addr(opKeyA)));
    }
}

/// @notice Invariant suite focusing on operator accounting.
contract EigenShieldHookOperatorInvariant is StdInvariant, Test, BaseTest {
    using PoolIdLibrary for PoolKey;

    EigenShieldHook internal hook;
    OperatorHandler internal handler;
    address[] internal ops;

    function setUp() public {
        vm.warp(1_700_000_000);
        deployArtifactsAndLabel();

        (Currency currency0, Currency currency1) = deployCurrencyPair();
        currency0; currency1;

        address flags = address(uint160(Hooks.BEFORE_SWAP_FLAG) ^ (0xDEAD << 144));

        ops = new address[](5);
        for (uint256 i = 0; i < ops.length; i++) {
            ops[i] = vm.addr(uint256(keccak256(abi.encode("op", i))));
        }

        bytes memory constructorArgs =
            abi.encode(poolManager, ops, uint16(6700), uint8(60), uint32(300));
        deployCodeTo("EigenShieldHook.sol:EigenShieldHook", constructorArgs, flags);
        hook = EigenShieldHook(flags);

        handler = new OperatorHandler(hook, address(this), ops);
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = handler.toggle.selector;
        selectors[1] = handler.bumpQuorum.selector;
        selectors[2] = handler.bumpMinConfidence.selector;
        selectors[3] = handler.bumpFreshnessWindow.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_operatorCountMatchesActiveSet() public view {
        uint256 active;
        for (uint256 i = 0; i < ops.length; i++) {
            if (hook.isOperator(ops[i])) {
                active++;
            }
        }
        assertEq(active, hook.operatorCount(), "operator count drift");
    }
}

contract OperatorHandler is Test {
    EigenShieldHook internal hook;
    address internal guardian;
    address[] internal ops;

    constructor(EigenShieldHook _hook, address _guardian, address[] memory _ops) {
        hook = _hook;
        guardian = _guardian;
        ops = _ops;
    }

    function toggle(uint256 seed, bool active) external {
        address[] memory arr = new address[](1);
        arr[0] = ops[seed % ops.length];
        vm.prank(guardian);
        hook.setOperators(arr, active);
    }

    function bumpQuorum(uint16 delta) external {
        uint16 newQuorum = uint16(1 + (delta % 9999));
        vm.prank(guardian);
        hook.updateQuorum(newQuorum);
    }

    function bumpMinConfidence(uint8 v) external {
        vm.prank(guardian);
        hook.updateMinConfidence(v);
    }

    function bumpFreshnessWindow(uint32 v) external {
        vm.prank(guardian);
        hook.updateFreshnessWindow(v + 1);
    }
}

