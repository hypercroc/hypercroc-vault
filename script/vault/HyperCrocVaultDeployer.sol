// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {HyperCrocVaultFactory} from "contracts/HyperCrocVaultFactory.sol";
import {HyperCrocVault} from "contracts/HyperCrocVault.sol";
import {WithdrawalQueue} from "contracts/WithdrawalQueue.sol";
import {ChainValues} from "../helper/ChainValues.sol";
import {DeployHelper} from "../helper/DeployHelper.sol";
import {Adapter, AdapterUtils} from "../helper/AdapterUtils.sol";
import {DeployHyperCrocVaultFactory} from "../DeployHyperCrocVaultFactory.s.sol";
import {Adapter, DeployAdapter} from "../DeployAdapter.s.sol";

struct VaultConfig {
    string deploymentId;
    address asset;
    address feeCollector;
    address eulerOracle;
    string lpName;
    string lpSymbol;
    string withdrawalQueueName;
    string withdrawalQueueSymbol;
    address[] trackedAssets;
    uint48 performanceFee;
    uint48 managementFee;
    Adapter[] adapters;
    address vaultManager;
    uint24 maxSlippage;
    uint8 maxExternalPositionAdapters;
    uint8 maxTrackedAssets;
    uint256 initialDeposit;
    address withdrawQueueFinalizer;
    uint256 minDepositAmount;
}

abstract contract HyperCrocVaultDeployer is DeployHelper, AdapterUtils {
    using stdJson for string;

    string public constant DEPLOYMENT_FILE = "vaults.json";

    function run() external virtual {
        VaultConfig[] memory deployConfigs = _getDeployConfig();

        for (uint256 i = 0; i < deployConfigs.length; i++) {
            VaultConfig memory deployConfig = deployConfigs[i];

            HyperCrocVault vault = _deployVault(deployConfig);
            _deployAdapters(deployConfig, vault);

            // check
            uint256 totalAssets = vault.totalAssets();
            uint256 totalSupply = vault.totalSupply();
            if (deployConfig.initialDeposit != 0) {
                assert(totalAssets == deployConfig.initialDeposit);
                assert(totalSupply == deployConfig.initialDeposit);
            }

            _saveDeploymentState(deployConfig, address(vault));
        }
    }

    ///@dev Deploy and configure vault
    function _deployVault(VaultConfig memory config) internal returns (HyperCrocVault vault) {
        //HyperCrocVault factory should be deployed first
        HyperCrocVaultFactory factory = HyperCrocVaultFactory(getAddress("HyperCrocVaultFactory"));

        //skip deployment if already deployed
        address deployedVault = _getDeployedAddress(config.deploymentId);
        if (deployedVault == address(0)) {
            vm.startBroadcast();
            (deployedVault,) = factory.deployVault(
                config.asset,
                config.lpName,
                config.lpSymbol,
                config.withdrawalQueueName,
                config.withdrawalQueueSymbol,
                config.feeCollector,
                config.eulerOracle
            );
            vm.stopBroadcast();
        }

        vault = HyperCrocVault(deployedVault);

        if (!vault.isVaultManager(config.vaultManager)) {
            vm.startBroadcast();
            vault.addVaultManager(config.vaultManager, true);
            vm.stopBroadcast();
        }

        if (vault.maxSlippage() != config.maxSlippage) {
            vm.startBroadcast();
            vault.setMaxSlippage(config.maxSlippage);
            vm.stopBroadcast();
        }

        if (vault.maxExternalPositionAdapters() != config.maxExternalPositionAdapters) {
            vm.startBroadcast();
            vault.setMaxExternalPositionAdapters(config.maxExternalPositionAdapters);
            vm.stopBroadcast();
        }

        if (vault.maxTrackedAssets() != config.maxTrackedAssets) {
            vm.startBroadcast();
            vault.setMaxTrackedAssets(config.maxTrackedAssets);
            vm.stopBroadcast();
        }

        if (config.managementFee != 0) {
            vm.startBroadcast();
            vault.setManagementFeeIR(config.managementFee);
            vm.stopBroadcast();
        }

        if (config.performanceFee != 0) {
            vm.startBroadcast();
            vault.setPerformanceFeeRatio(config.performanceFee);
            vm.stopBroadcast();
        }

        WithdrawalQueue withdrawalQueue = WithdrawalQueue(vault.withdrawalQueue());
        if (!withdrawalQueue.isFinalizer(config.withdrawQueueFinalizer)) {
            vm.startBroadcast();
            withdrawalQueue.addFinalizer(config.withdrawQueueFinalizer, true);
            vm.stopBroadcast();
        }

        //initial deposit
        if (config.initialDeposit != 0 && vault.totalAssets() == 0) {
            address vaultManager = getAddress("VaultManager");
            vm.startBroadcast();
            IERC20(config.asset).approve(address(vault), config.initialDeposit);
            vault.deposit(config.initialDeposit, vaultManager);
            require(vault.balanceOf(vaultManager) != 0);
            vm.stopBroadcast();
        }

        if (vault.minimalDeposit() != config.minDepositAmount) {
            vm.startBroadcast();
            vault.setMinimalDeposit(config.minDepositAmount);
            vm.stopBroadcast();
        }

        //configure tracked assets
        for (uint256 i = 0; i < config.trackedAssets.length; ++i) {
            if (vault.trackedAssetPosition(config.trackedAssets[i]) == 0) {
                vm.startBroadcast();
                vault.addTrackedAsset(config.trackedAssets[i]);
                vm.stopBroadcast();
            }
        }

        return vault;
    }

    function _deployAdapters(VaultConfig memory config, HyperCrocVault vault) internal {
        DeployAdapter adapterDeployer = new DeployAdapter();

        for (uint256 i = 0; i < config.adapters.length; ++i) {
            Adapter adapter = config.adapters[i];

            //skip if adapter already connected
            bytes4 adapterId = _getAdapterId(adapter);
            if (address(vault.getAdapter(adapterId)) != address(0)) {
                continue;
            }

            address adapterAddress = adapterDeployer.getOrDeployAdapter(adapter, address(vault));

            vm.startBroadcast();
            vault.addAdapter(adapterAddress);
            vm.stopBroadcast();
        }
    }

    function _getDeployedAddress(string memory deploymentId) internal view returns (address) {
        return _readAddressFromDeployment(DEPLOYMENT_FILE, deploymentId);
    }

    function _saveDeploymentState(VaultConfig memory config, address vault) internal {
        string memory path = _getDeploymentPath(DEPLOYMENT_FILE);
        _saveInDeploymentFile(path, config.deploymentId, vault);
    }

    function _getDeployConfig() internal view virtual returns (VaultConfig[] memory);
}
