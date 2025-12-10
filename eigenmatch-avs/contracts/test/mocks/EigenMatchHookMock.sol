// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IEigenShieldHook, PoolId} from "@project/interfaces/IEigenMatchHook.sol";

contract EigenShieldHookMock is IEigenShieldHook {
    PoolId public lastPoolId;
    bytes32 public lastBundleId;
    uint256 public lastVerdictCount;

    event BundleProcessed(PoolId indexed poolId, bytes32 indexed bundleId);

    function submitVerdictBundle(PoolId poolId, VerdictBundle calldata bundle) external override {
        lastPoolId = poolId;
        lastBundleId = bundle.bundleId;
        lastVerdictCount = bundle.verdicts.length;
        emit BundleProcessed(poolId, bundle.bundleId);
    }
}

