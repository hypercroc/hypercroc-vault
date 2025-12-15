// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import {Asserts} from "../libraries/Asserts.sol";

abstract contract WithdrawalQueueBase is Initializable, Ownable2StepUpgradeable {
    using Asserts for address;

    /// @custom:storage-location erc7201:hyperCroc.storage.WithdrawalQueueBaseStorage
    struct WithdrawalQueueBaseStorage {
        uint256 lastRequestId;
        uint256 lastFinalizedRequestId;
        IERC4626 hyperCrocVault;
        mapping(address => bool) finalizers;
        mapping(uint256 requestId => uint256) requestedShares;
    }

    /// @dev 'WithdrawalQueueStorageData' storage slot address
    /// @dev keccak256(abi.encode(uint256(keccak256("hyperCroc-vault.WithdrawalQueueBaseStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WithdrawalQueueBaseStorageLocation =
        0x78f0351b059b6aed2e654ce4a38d42d975f3dcea3167a2d4518f5ef39639c600;

    function _getWithdrawalQueueBaseStorage() private pure returns (WithdrawalQueueBaseStorage storage $) {
        assembly {
            $.slot := WithdrawalQueueBaseStorageLocation
        }
    }

    event FinalizerSet(address indexed finalizer, bool added);

    error NoAccess(address sender);
    error FutureFinalization();
    error AlreadyFinalized();

    modifier onlyHyperCrocVault() {
        _onlyHyperCrocVault();
        _;
    }

    modifier onlyFinalizer() {
        _onlyFinalizer();
        _;
    }

    function __WithdrawalQueueBase_init(address owner, address _hyperCrocVault) internal onlyInitializing {
        __Ownable_init(owner);

        _hyperCrocVault.assertNotZeroAddress();
        _getWithdrawalQueueBaseStorage().hyperCrocVault = IERC4626(_hyperCrocVault);
    }

    function addFinalizer(address finalizer, bool add) external onlyOwner {
        finalizer.assertNotZeroAddress();
        _getWithdrawalQueueBaseStorage().finalizers[finalizer] = add;
        emit FinalizerSet(finalizer, add);
    }

    function getRequestedShares(uint256 requestId) external view returns (uint256) {
        return _getRequestedShares(requestId);
    }

    function hyperCrocVault() external view returns (IERC4626) {
        return _getHyperCrocVault();
    }

    function lastRequestId() external view returns (uint256) {
        return _getWithdrawalQueueBaseStorage().lastRequestId;
    }

    function lastFinalizedRequestId() external view returns (uint256) {
        return _getWithdrawalQueueBaseStorage().lastFinalizedRequestId;
    }

    function isFinalizer(address finalizer) external view returns (bool) {
        return _getWithdrawalQueueBaseStorage().finalizers[finalizer];
    }

    function _enqueueRequest(uint256 shares) internal returns (uint256 requestId) {
        WithdrawalQueueBaseStorage storage queue = _getWithdrawalQueueBaseStorage();
        unchecked {
            requestId = ++queue.lastRequestId;
        }
        queue.requestedShares[requestId] = shares;
    }

    function _removeRequest(uint256 requestId) internal returns (uint256 requestedShares) {
        WithdrawalQueueBaseStorage storage queue = _getWithdrawalQueueBaseStorage();
        requestedShares = queue.requestedShares[requestId];
        delete queue.requestedShares[requestId];
    }

    function _finalizeRequests(uint256 newLastFinalizedRequestId) internal {
        WithdrawalQueueBaseStorage storage queue = _getWithdrawalQueueBaseStorage();
        if (queue.lastFinalizedRequestId >= newLastFinalizedRequestId) revert AlreadyFinalized();
        if (queue.lastRequestId < newLastFinalizedRequestId) revert FutureFinalization();

        queue.lastFinalizedRequestId = newLastFinalizedRequestId;
    }

    function _getRequestedShares(uint256 requestId) internal view returns (uint256) {
        WithdrawalQueueBaseStorage storage queue = _getWithdrawalQueueBaseStorage();
        return queue.requestedShares[requestId];
    }

    function _getHyperCrocVault() internal view returns (IERC4626) {
        return _getWithdrawalQueueBaseStorage().hyperCrocVault;
    }

    function _isFinalized(uint256 requestId) internal view returns (bool) {
        return requestId <= _getWithdrawalQueueBaseStorage().lastFinalizedRequestId;
    }

    function _onlyHyperCrocVault() private view {
        if (msg.sender != address(_getHyperCrocVault())) revert NoAccess(msg.sender);
    }

    function _onlyFinalizer() private view {
        if (!_getWithdrawalQueueBaseStorage().finalizers[msg.sender]) revert NoAccess(msg.sender);
    }
}
