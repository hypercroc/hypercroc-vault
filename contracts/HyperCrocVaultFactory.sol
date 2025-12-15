// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {FactoryBase} from "./base/FactoryBase.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract HyperCrocVaultFactory is UUPSUpgradeable, FactoryBase {
    error Forbidden();

    /// @dev Disabling initializers for implementation contract
    constructor() {
        _disableInitializers();
    }

    function initialize(address vaultImplementation, address withdrawalQueueImplementation) external initializer {
        __FactoryBase_init(msg.sender, vaultImplementation, withdrawalQueueImplementation);
    }

    function deployVault(
        address asset,
        string calldata lpName,
        string calldata lpSymbol,
        string calldata withdrawalQueueName,
        string calldata withdrawalQueueSymbol,
        address feeCollector,
        address eulerOracle
    ) external onlyOwner returns (address vault, address queue) {
        return
            _deployVault(asset, lpName, lpSymbol, withdrawalQueueName, withdrawalQueueSymbol, feeCollector, eulerOracle);
    }

    function renounceOwnership() public pure override {
        revert Forbidden();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
