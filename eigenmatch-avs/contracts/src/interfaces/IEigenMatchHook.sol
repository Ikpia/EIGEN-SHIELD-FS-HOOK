// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

type PoolId is bytes32;

interface IEigenShieldHook {
    /// @notice Individual operator verdict emitted by EigenCompute/EigenAI detection.
    struct OperatorVerdict {
        address operator;
        bool isSafe;
        uint8 confidence; // 0-100
        bytes32 contextHash; // hashed mempool slice & heuristics for accountability
    }

    /// @notice Bundle of operator verdicts tied to a specific detection build.
    struct VerdictBundle {
        uint64 observedAt;
        bytes32 bundleId;
        bytes32 teeMeasurement;
        bytes32 dockerDigest;
        bytes32 replaySalt;
        OperatorVerdict[] verdicts;
    }

    /// @notice Deliver a verified verdict bundle for a pool.
    function submitVerdictBundle(
        PoolId poolId,
        VerdictBundle calldata bundle
    ) external;
}

