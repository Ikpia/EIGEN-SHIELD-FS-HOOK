// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {EigenShieldHook} from "../src/EigenShieldHook.sol";

/// @notice Deploys EigenShieldHook to Base Sepolia
contract DeployBaseSepoliaScript is Script {
    // Base Sepolia Uniswap V4 Pool Manager
    address internal constant BASE_SEPOLIA_POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);

        // Initial operators (can be updated later by guardian)
        address[] memory operators = new address[](3);
        operators[0] = vm.addr(11);
        operators[1] = vm.addr(22);
        operators[2] = vm.addr(33);

        uint16 quorumBps = 6700; // 67% quorum
        uint8 minConfidence = 60; // minimum confidence threshold (0-100)
        uint32 freshnessWindow = 300; // seconds

        bytes memory constructorArgs =
            abi.encode(BASE_SEPOLIA_POOL_MANAGER, operators, quorumBps, minConfidence, freshnessWindow);
        
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(EigenShieldHook).creationCode, constructorArgs);

        console.log("Mined Hook Address:", hookAddress);
        console.log("Salt:", vm.toString(salt));

        // Deploy the hook using CREATE2
        EigenShieldHook hook =
            new EigenShieldHook{salt: salt}(IPoolManager(BASE_SEPOLIA_POOL_MANAGER), operators, quorumBps, minConfidence, freshnessWindow);

        require(address(hook) == hookAddress, "DeployBaseSepoliaScript: Hook Address Mismatch");

        console.log("EigenShieldHook deployed at:", address(hook));
        console.log("Pool Manager:", BASE_SEPOLIA_POOL_MANAGER);
        console.log("Quorum BPS:", quorumBps);
        console.log("Min Confidence:", minConfidence);
        console.log("Freshness Window:", freshnessWindow);
        console.log("Operators:");
        for (uint256 i = 0; i < operators.length; i++) {
            console.log("  Operator", i, ":", operators[i]);
        }

        vm.stopBroadcast();
    }
}

