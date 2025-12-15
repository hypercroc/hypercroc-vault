// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import {Asserts} from "../libraries/Asserts.sol";

abstract contract VaultAccessControl is Initializable, Ownable2StepUpgradeable {
    using Asserts for address;

    /// @custom:storage-location erc7201:hyperCroc.storage.VaultAccessControlStorage
    struct VaultAccessControlStorage {
        address withdrawalQueue;
        /// @dev vault managers
        mapping(address => bool) _vaultManagers;
    }

    /// @dev 'VaultAccessControlStorage' storage slot address
    /// @dev keccak256(abi.encode(uint256(keccak256("hyperCroc-vault.VaultAccessControlStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VaultAccessControlStorageLocation =
        0x02eb9da8ea38b41b4650ef2b85e08be861a787c9657df49bae75bf68e905cf00;

    /// @dev returns storage slot of 'VaultAccessControlStorage' struct
    function _getVaultAccessControlStorage() private pure returns (VaultAccessControlStorage storage $) {
        assembly {
            $.slot := VaultAccessControlStorageLocation
        }
    }

    event VaultManagerSet(address indexed manager, bool added);
    event QueueSet(address indexed queue);

    error NoAccess(address sender);

    modifier onlyVaultManager() {
        _onlyVaultManager();
        _;
    }

    modifier onlyQueue() {
        _onlyQueue();
        _;
    }

    function __VaultAccessControl_init(address owner, address _withdrawalQueue) internal onlyInitializing {
        _withdrawalQueue.assertNotZeroAddress();
        owner.assertNotZeroAddress();

        __Ownable_init(owner);
        _getVaultAccessControlStorage().withdrawalQueue = _withdrawalQueue;
    }

    function addVaultManager(address manager, bool add) external onlyOwner {
        manager.assertNotZeroAddress();
        _getVaultAccessControlStorage()._vaultManagers[manager] = add;
        emit VaultManagerSet(manager, add);
    }

    function withdrawalQueue() external view returns (address) {
        return _getWithdrawalQueue();
    }

    function isVaultManager(address manager) external view returns (bool) {
        return _getVaultAccessControlStorage()._vaultManagers[manager];
    }

    function _getWithdrawalQueue() internal view returns (address) {
        return _getVaultAccessControlStorage().withdrawalQueue;
    }

    function _onlyVaultManager() private view {
        if (!_getVaultAccessControlStorage()._vaultManagers[msg.sender]) revert NoAccess(msg.sender);
    }

    function _onlyQueue() private view {
        if (msg.sender != _getWithdrawalQueue()) revert NoAccess(msg.sender);
    }
}
