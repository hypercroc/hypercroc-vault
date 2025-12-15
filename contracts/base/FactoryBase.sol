// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {HyperCrocVault} from "../HyperCrocVault.sol";
import {WithdrawalQueue} from "../WithdrawalQueue.sol";

abstract contract FactoryBase is Initializable, Ownable2StepUpgradeable {
    /// @custom:storage-location erc7201:hyperCroc.storage.FactoryBase
    struct FactoryBaseStorage {
        mapping(address => bool) isHyperCrocVault;
        UpgradeableBeacon vaultBeacon;
        UpgradeableBeacon withdrawalQueueBeacon;
    }

    // keccak256(abi.encode(uint256(keccak256("hyperCroc.storage.FactoryBase")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FactoryBaseStorageLocation =
        0xcc8f7fa260fdbb6100fec3c743c29c0691eb5ad58bd519936bac66b66bacb700;

    function _getFactoryBaseStorage() private pure returns (FactoryBaseStorage storage $) {
        assembly {
            $.slot := FactoryBaseStorageLocation
        }
    }

    event NewVaultDeployed(address asset, address indexed vault, address indexed withdrawalQueue, string lpName);

    function __FactoryBase_init(address owner, address vaultImplementation, address withdrawalQueueImplementation)
        internal
        onlyInitializing
    {
        __Ownable_init(owner);

        FactoryBaseStorage storage $ = _getFactoryBaseStorage();
        $.vaultBeacon = new UpgradeableBeacon(vaultImplementation, owner);
        $.withdrawalQueueBeacon = new UpgradeableBeacon(withdrawalQueueImplementation, owner);
    }

    function vaultBeacon() public view returns (address) {
        return address(_getFactoryBaseStorage().vaultBeacon);
    }

    function withdrawalQueueBeacon() public view returns (address) {
        return address(_getFactoryBaseStorage().withdrawalQueueBeacon);
    }

    function isHyperCrocVault(address hyperCrocVault) external view returns (bool) {
        return _getFactoryBaseStorage().isHyperCrocVault[hyperCrocVault];
    }

    function _deployVault(
        address asset,
        string calldata lpName,
        string calldata lpSymbol,
        string calldata withdrawalQueueName,
        string calldata withdrawalQueueSymbol,
        address feeCollector,
        address eulerOracle
    ) internal returns (address vault, address queue) {
        vault = address(new BeaconProxy(vaultBeacon(), ""));
        queue = _deployQueue(vault, withdrawalQueueName, withdrawalQueueSymbol);

        HyperCrocVault(vault).initialize(msg.sender, asset, lpName, lpSymbol, feeCollector, eulerOracle, queue);

        _getFactoryBaseStorage().isHyperCrocVault[vault] = true;

        emit NewVaultDeployed(asset, vault, queue, lpName);
    }

    function _deployQueue(address vault, string calldata withdrawalQueueName, string calldata withdrawalQueueSymbol)
        private
        returns (address queue)
    {
        bytes memory queueInitializeCalldata = abi.encodeWithSelector(
            WithdrawalQueue.initialize.selector, msg.sender, vault, withdrawalQueueName, withdrawalQueueSymbol
        );
        queue = address(new BeaconProxy(withdrawalQueueBeacon(), queueInitializeCalldata));
    }
}
