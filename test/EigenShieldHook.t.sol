// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {EigenShieldHook} from "../src/EigenShieldHook.sol";
import {BaseTest} from "./utils/BaseTest.sol";

contract EigenShieldHookTest is BaseTest {
    using PoolIdLibrary for PoolKey;

    EigenShieldHook hook;
    PoolKey poolKey;
    SwapParams swapParams;
    address trader;
    Currency currency0;
    Currency currency1;

    uint256 opKeyA = 0xA11CE;
    uint256 opKeyB = 0xB0B;
    uint256 opKeyC = 0xC0DE;

    function setUp() public {
        vm.warp(1_700_000_000); // use a stable timestamp to avoid underflow in tests
        deployArtifactsAndLabel();

        (currency0, currency1) = deployCurrencyPair();

        trader = makeAddr("trader");

        // configure operators and deploy hook to an address with BEFORE_SWAP flag
        address flags =
            address(uint160(Hooks.BEFORE_SWAP_FLAG) ^ (0x4444 << 144)); // namespace to avoid collisions

        address[] memory operators = new address[](3);
        operators[0] = vm.addr(opKeyA);
        operators[1] = vm.addr(opKeyB);
        operators[2] = vm.addr(opKeyC);

        bytes memory constructorArgs = abi.encode(poolManager, operators, uint16(6700), uint8(60), uint32(300));
        deployCodeTo("EigenShieldHook.sol:EigenShieldHook", constructorArgs, flags);
        hook = EigenShieldHook(flags);

        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));

        swapParams =
            SwapParams({zeroForOne: true, amountSpecified: -int256(1e18), sqrtPriceLimitX96: uint160(4_295_128_740)});
    }

    function testSafeQuorumAllowsSwap() public {
        bytes32 intentId = hook.computeIntentId(poolKey, swapParams, trader);
        EigenShieldHook.Attestation[] memory atts = new EigenShieldHook.Attestation[](3);
        atts[0] = _attest(opKeyA, true, intentId);
        atts[1] = _attest(opKeyB, true, intentId);
        atts[2] = _attest(opKeyC, true, intentId);

        bytes memory hookData =
            abi.encode(EigenShieldHook.AttestationBundle({intentId: intentId, attestations: atts}));

        vm.prank(address(poolManager));
        (bytes4 selector,,) = hook.beforeSwap(trader, poolKey, swapParams, hookData);

        assertEq(selector, hook.beforeSwap.selector);
    }

    function testMaliciousQuorumBlocksSwap() public {
        bytes32 intentId = hook.computeIntentId(poolKey, swapParams, trader);
        EigenShieldHook.Attestation[] memory atts = new EigenShieldHook.Attestation[](3);
        atts[0] = _attest(opKeyA, false, intentId);
        atts[1] = _attest(opKeyB, false, intentId);
        atts[2] = _attest(opKeyC, false, intentId);

        bytes memory hookData =
            abi.encode(EigenShieldHook.AttestationBundle({intentId: intentId, attestations: atts}));

        vm.expectRevert(EigenShieldHook.MaliciousQuorum.selector);
        vm.prank(address(poolManager));
        hook.beforeSwap(trader, poolKey, swapParams, hookData);
    }

    function testInsufficientSafeQuorumReverts() public {
        bytes32 intentId = hook.computeIntentId(poolKey, swapParams, trader);
        EigenShieldHook.Attestation[] memory atts = new EigenShieldHook.Attestation[](1);
        atts[0] = _attest(opKeyA, true, intentId);

        bytes memory hookData =
            abi.encode(EigenShieldHook.AttestationBundle({intentId: intentId, attestations: atts}));

        vm.expectRevert(EigenShieldHook.SafeQuorumNotMet.selector);
        vm.prank(address(poolManager));
        hook.beforeSwap(trader, poolKey, swapParams, hookData);
    }

    function testStaleAttestationReverts() public {
        bytes32 intentId = hook.computeIntentId(poolKey, swapParams, trader);
        EigenShieldHook.Attestation[] memory atts = new EigenShieldHook.Attestation[](3);

        EigenShieldHook.Attestation memory stale = _attest(opKeyA, true, intentId);
        stale.timestamp = uint64(block.timestamp - 1000);
        bytes32 digest = hook.hashAttestation(stale, poolKey, swapParams, intentId);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(opKeyA, digest);
        stale.signature = abi.encodePacked(r, s, v);

        atts[0] = stale;
        atts[1] = _attest(opKeyB, true, intentId);
        atts[2] = _attest(opKeyC, true, intentId);

        bytes memory hookData =
            abi.encode(EigenShieldHook.AttestationBundle({intentId: intentId, attestations: atts}));

        vm.expectRevert(abi.encodeWithSelector(EigenShieldHook.StaleAttestation.selector, vm.addr(opKeyA)));
        vm.prank(address(poolManager));
        hook.beforeSwap(trader, poolKey, swapParams, hookData);
    }

    function _attest(uint256 pk, bool isSafe, bytes32 intentId)
        internal
        view
        returns (EigenShieldHook.Attestation memory att)
    {
        att = EigenShieldHook.Attestation({
            operator: vm.addr(pk),
            isSafe: isSafe,
            confidence: 90,
            timestamp: uint64(block.timestamp),
            signature: ""
        });

        bytes32 digest = hook.hashAttestation(att, poolKey, swapParams, intentId);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        att.signature = abi.encodePacked(r, s, v);
    }
}

