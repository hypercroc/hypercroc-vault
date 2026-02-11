// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {HyperCrocVaultFactory} from "contracts/HyperCrocVaultFactory.sol";
import {HyperCrocVault} from "contracts/HyperCrocVault.sol";
import {WithdrawalQueue} from "contracts/WithdrawalQueue.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ChainValues} from "../helper/ChainValues.sol";
import {Adapter} from "../helper/AdapterUtils.sol";
import {VaultConfig, HyperCrocVaultDeployer} from "./HyperCrocVaultDeployer.sol";
import {DeployHelper} from "../helper/DeployHelper.sol";
import {DeployHyperCrocVaultFactory} from "../DeployHyperCrocVaultFactory.s.sol";
import {Adapter, DeployAdapter} from "../DeployAdapter.s.sol";

///@dev forge script script/vault/DeployUSDTFlagshipVault.s.sol:DeployUSDTFlagshipVault -vvvv --account testDeployer --rpc-url $HYPER_RPC_URL
contract DeployUSDTFlagshipVault is HyperCrocVaultDeployer {
    using stdJson for string;
    using Strings for address;

    function _getDeployConfig() internal view override returns (VaultConfig[] memory configs) {
        if (block.chainid == 999) {
            address[] memory trackedAssets = new address[](5);
            trackedAssets[0] = getAddress("hbUSDT");
            trackedAssets[1] = getAddress("hUSDT");
            trackedAssets[2] = getAddress("wHYPE");
            trackedAssets[3] = getAddress("UBTC");
            trackedAssets[4] = getAddress("UETH");

            Adapter[] memory adapters = new Adapter[](0);

            VaultConfig memory config = VaultConfig({
                deploymentId: "Hyper-croc-flagship-vault",
                asset: getAddress("USDT"),
                feeCollector: getAddress("FeeCollector"),
                eulerOracle: getAddress("EulerOracle"),
                lpName: "HyperCroc Maximum Growth Portfolio",
                lpSymbol: "hUSDCmaxG",
                withdrawalQueueName: "Withdraw Voucher hUSDCmaxG",
                withdrawalQueueSymbol: "WVhUSDCmaxG",
                trackedAssets: trackedAssets,
                performanceFee: 100_000, // 10%
                managementFee: 5_000, // 0.5%
                adapters: adapters,
                vaultManager: getAddress("VaultManager"),
                maxSlippage: 1_000,
                maxExternalPositionAdapters: 15,
                maxTrackedAssets: 15,
                initialDeposit: 1_000_000,
                withdrawQueueFinalizer: getAddress("WithdrawalQueueFinalizer"),
                minDepositAmount: 1_000_000
            });

            configs = new VaultConfig[](1);
            configs[0] = config;
            return configs;
        }

        revert("Config not found for chainId");
    }
}
