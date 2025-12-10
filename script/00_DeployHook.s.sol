// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {BaseScript} from "./base/BaseScript.sol";

import {EigenShieldHook} from "../src/EigenShieldHook.sol";

/// @notice Mines the address and deploys the EigenShieldHook contract
contract DeployHookScript is BaseScript {
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);

        // Mine a salt that will produce a hook address with the correct flags
        address[] memory operators = new address[](3);
        operators[0] = vm.addr(11);
        operators[1] = vm.addr(22);
        operators[2] = vm.addr(33);

        uint16 quorumBps = 6700; // 67% quorum
        uint8 minConfidence = 60; // minimum confidence threshold (0-100)
        uint32 freshnessWindow = 300; // seconds

        bytes memory constructorArgs =
            abi.encode(poolManager, operators, quorumBps, minConfidence, freshnessWindow);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(EigenShieldHook).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.startBroadcast();
        EigenShieldHook hook =
            new EigenShieldHook{salt: salt}(poolManager, operators, quorumBps, minConfidence, freshnessWindow);
        vm.stopBroadcast();

        require(address(hook) == hookAddress, "DeployHookScript: Hook Address Mismatch");
    }
}
