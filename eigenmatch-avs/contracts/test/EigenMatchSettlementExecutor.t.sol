// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {IEigenShieldHook, PoolId} from "@project/interfaces/IEigenMatchHook.sol";
import {EigenShieldDigestRegistry} from "@project/l1-contracts/EigenMatchDigestRegistry.sol";
import {EigenShieldAttestationRelay} from "@project/l2-contracts/EigenMatchSettlementExecutor.sol";
import {EigenShieldHookMock} from "test/mocks/EigenMatchHookMock.sol";

contract EigenShieldAttestationRelayTest is Test {
    EigenShieldDigestRegistry private registry;
    EigenShieldAttestationRelay private executor;
    EigenShieldHookMock private hook;

    address private watcher;
    uint256 private watcherKey;
    address private watcherTwo;
    uint256 private watcherTwoKey;

    bytes32 private constant MEASUREMENT = keccak256("measurement");
    bytes32 private constant DIGEST = keccak256("digest");

    function setUp() public {
        registry = new EigenShieldDigestRegistry(address(this));
        registry.setMeasurementAllowed(MEASUREMENT, true);
        registry.publishDigest(DIGEST, MEASUREMENT, "ipfs://digest");

        hook = new EigenShieldHookMock();
        (watcher, watcherKey) = makeAddrAndKey("watcher");
        (watcherTwo, watcherTwoKey) = makeAddrAndKey("watcher-two");

        address[] memory watchers = new address[](2);
        watchers[0] = watcher;
        watchers[1] = watcherTwo;

        executor = new EigenShieldAttestationRelay(hook, registry, address(this), watchers, 1);
    }

    function testSubmitSettlementForwardsToHook() public {
        EigenShieldAttestationRelay.BundleSubmission memory submission = _buildSubmission();
        submission.watcherSignatures = _signDefault(submission.bundle.bundleId, submission.bundle.replaySalt);

        executor.submitSettlement(submission);

        assertEq(hook.lastBundleId(), submission.bundle.bundleId);
        assertEq(hook.lastVerdictCount(), submission.bundle.verdicts.length);
    }

    function testSubmitSettlementRevertsWhenDigestRevoked() public {
        EigenShieldAttestationRelay.BundleSubmission memory submission = _buildSubmission();
        registry.setDigestRevoked(DIGEST, true);
        submission.watcherSignatures = _signDefault(submission.bundle.bundleId, submission.bundle.replaySalt);

        vm.expectRevert(
            abi.encodeWithSelector(
                EigenShieldAttestationRelay.DigestNotAuthorized.selector, DIGEST, MEASUREMENT
            )
        );
        executor.submitSettlement(submission);
    }

    function testSubmitSettlementRejectsInsufficientSigners() public {
        EigenShieldAttestationRelay.BundleSubmission memory submission = _buildSubmission();
        submission.watcherSignatures = new bytes[](0);

        vm.expectRevert(
            abi.encodeWithSelector(EigenShieldAttestationRelay.InsufficientWatcherSigners.selector, 1, 0)
        );
        executor.submitSettlement(submission);
    }

    function testSubmitSettlementRejectsDuplicateWatcherSignatures() public {
        EigenShieldAttestationRelay local =
            new EigenShieldAttestationRelay(hook, registry, address(this), _twoWatchers(), 2);
        EigenShieldAttestationRelay.BundleSubmission memory submission = _buildSubmission();

        bytes32 digest = local.watcherMessageHash(submission.bundle.bundleId, submission.bundle.replaySalt);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(watcherKey, digest);

        submission.watcherSignatures = new bytes[](2);
        submission.watcherSignatures[0] = abi.encodePacked(r, s, v);
        submission.watcherSignatures[1] = abi.encodePacked(r, s, v);

        vm.expectRevert(
            abi.encodeWithSelector(EigenShieldAttestationRelay.DuplicateWatcherSignature.selector, watcher)
        );
        local.submitSettlement(submission);
    }

    function testSubmitSettlementRejectsUnknownWatcherSignature() public {
        EigenShieldAttestationRelay.BundleSubmission memory submission = _buildSubmission();
        bytes32 digest = executor.watcherMessageHash(submission.bundle.bundleId, submission.bundle.replaySalt);
        (address stranger, uint256 strangerKey) = makeAddrAndKey("stranger");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(strangerKey, digest);
        submission.watcherSignatures = new bytes[](1);
        submission.watcherSignatures[0] = abi.encodePacked(r, s, v);

        vm.expectRevert(
            abi.encodeWithSelector(EigenShieldAttestationRelay.InvalidWatcherSignature.selector, stranger)
        );
        executor.submitSettlement(submission);
    }

    function testSubmitSettlementRejectsDuplicateBundles() public {
        EigenShieldAttestationRelay.BundleSubmission memory submission = _buildSubmission();
        submission.watcherSignatures = _signDefault(submission.bundle.bundleId, submission.bundle.replaySalt);
        executor.submitSettlement(submission);

        vm.expectRevert(
            abi.encodeWithSelector(EigenShieldAttestationRelay.BundleAlreadyProcessed.selector, submission.bundle.bundleId)
        );
        executor.submitSettlement(submission);
    }

    function _buildSubmission() private view returns (EigenShieldAttestationRelay.BundleSubmission memory submission) {
        IEigenShieldHook.OperatorVerdict[] memory verdicts = new IEigenShieldHook.OperatorVerdict[](2);
        verdicts[0] = IEigenShieldHook.OperatorVerdict({
            operator: watcher,
            isSafe: true,
            confidence: 90,
            contextHash: keccak256("ctx-a")
        });
        verdicts[1] = IEigenShieldHook.OperatorVerdict({
            operator: watcherTwo,
            isSafe: true,
            confidence: 85,
            contextHash: keccak256("ctx-b")
        });

        submission.poolId = PoolId.wrap(bytes32(uint256(1234)));
        submission.bundle = IEigenShieldHook.VerdictBundle({
            observedAt: uint64(block.timestamp),
            bundleId: keccak256("bundle"),
            teeMeasurement: MEASUREMENT,
            dockerDigest: DIGEST,
            replaySalt: keccak256("salt"),
            verdicts: verdicts
        });
    }

    function _signDefault(bytes32 bundleId, bytes32 replaySalt) private view returns (bytes[] memory sigs) {
        bytes32 digest = executor.watcherMessageHash(bundleId, replaySalt);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(watcherKey, digest);
        sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
    }

    function _twoWatchers() private view returns (address[] memory watchers) {
        watchers = new address[](2);
        watchers[0] = watcher;
        watchers[1] = watcherTwo;
    }
}
