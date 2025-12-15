// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {HyperCrocVaultFactory} from "contracts/HyperCrocVaultFactory.sol";
import {HyperCrocVault} from "contracts/HyperCrocVault.sol";
import {WithdrawalQueue} from "contracts/WithdrawalQueue.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ChainValues} from "./helper/ChainValues.sol";
import {DeployHelper} from "./helper/DeployHelper.sol";
import {Adapter, AdapterUtils} from "./helper/AdapterUtils.sol";
import {AaveAdapter} from "contracts/adapters/aave/AaveAdapter.sol";
import {CurveRouterAdapter} from "contracts/adapters/curve/CurveRouterAdapter.sol";
import {EthenaAdapter} from "contracts/adapters/ethena/EthenaAdapter.sol";
import {EtherfiETHAdapter} from "contracts/adapters/etherfi/EtherfiETHAdapter.sol";
import {EtherfiBTCAdapter} from "contracts/adapters/etherfi/EtherfiBTCAdapter.sol";
import {HyperCrocPoolAdapter} from "contracts/adapters/hyperCrocPool/HyperCrocPoolAdapter.sol";
import {HyperCrocVaultAdapter} from "contracts/adapters/hyperCrocVault/HyperCrocVaultAdapter.sol";
import {LidoAdapter} from "contracts/adapters/lido/LidoAdapter.sol";
import {MakerDaoDaiAdapter} from "contracts/adapters/makerDao/MakerDaoDaiAdapter.sol";
import {MakerDaoUsdsAdapter} from "contracts/adapters/makerDao/MakerDaoUsdsAdapter.sol";
import {MorphoAdapter} from "contracts/adapters/morpho/MorphoAdapter.sol";
import {MorphoAdapterV1_1} from "contracts/adapters/morpho/MorphoAdapterV1_1.sol";
import {UniswapAdapter} from "contracts/adapters/uniswap/UniswapAdapter.sol";
import {PendleAdapter} from "contracts/adapters/pendle/PendleAdapter.sol";
import {ResolvAdapter} from "contracts/adapters/resolv/ResolvAdapter.sol";
import {DeployHyperCrocVaultFactory} from "./DeployHyperCrocVaultFactory.s.sol";

/**
 * @dev Uncomment lines you want to deploy
 * @dev source .env && forge script script/DeployAdapter.s.sol:DeployAdapter -vvvv --account testDeployer --rpc-url $ETH_RPC_URL
 */
contract DeployAdapter is DeployHelper, AdapterUtils {
    using stdJson for string;

    string public constant DEPLOYMENT_FILE = "adapters.json";

    function run() public {
        deployAdapter(Adapter.AaveAdapter, address(0));
        deployAdapter(Adapter.CurveRouterAdapter, address(0));
        deployAdapter(Adapter.EthenaAdapter, address(0));
        deployAdapter(Adapter.EtherfiBTC, address(0));
        deployAdapter(Adapter.EtherfiETH, address(0));
        deployAdapter(Adapter.HyperCrocPoolAdapter, address(0));
        deployAdapter(Adapter.HyperCrocVaultAdapter, address(0));
        deployAdapter(Adapter.Lido, address(0));
        deployAdapter(Adapter.MakerDaoDAI, address(0));
        deployAdapter(Adapter.MakerDaoUSDS, address(0));
        deployAdapter(Adapter.Morpho, address(0));
        deployAdapter(Adapter.MorphoV1_1, address(0));
        deployAdapter(Adapter.PendleAdapter, address(0));
        deployAdapter(Adapter.UniswapAdapter, address(0));
        deployAdapter(Adapter.ResolvAdapter, address(0));
    }

    function getDeployedAdapter(Adapter adapter, address vault) public view returns (address) {
        string memory deploymentKey = _getAdapterName(adapter);
        if (_isPerVaultAdapter(adapter)) {
            deploymentKey = string.concat(deploymentKey, "_", vm.toString(vault));
        }

        return _readAddressFromDeployment(DEPLOYMENT_FILE, deploymentKey);
    }

    function deployAdapterAndConnectToVault(Adapter adapter, address vaultAddress) public {
        address deployedAdapter = deployAdapter(adapter, vaultAddress);

        HyperCrocVault vault = HyperCrocVault(vaultAddress);

        vm.broadcast();
        vault.addAdapter(deployedAdapter);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOY ADAPTERS
    //////////////////////////////////////////////////////////////*/

    function getOrDeployAdapter(Adapter adapter, address vault) public returns (address deployedAdapter) {
        deployedAdapter = getDeployedAdapter(adapter, address(vault));
        if (deployedAdapter == address(0)) {
            deployedAdapter = deployAdapter(adapter, address(vault));
        }
    }

    function deployAdapter(Adapter adapter, address hyperCrocVault) public returns (address deployedAdapter) {
        if (adapter == Adapter.AaveAdapter) {
            deployedAdapter = _deployAave();
        } else if (adapter == Adapter.CurveRouterAdapter) {
            deployedAdapter = _deployCurveRouter();
        } else if (adapter == Adapter.EthenaAdapter) {
            deployedAdapter = _deployEthena(hyperCrocVault);
        } else if (adapter == Adapter.EtherfiETH) {
            deployedAdapter = _deployEtherfiETH();
        } else if (adapter == Adapter.EtherfiBTC) {
            deployedAdapter = _deployEtherfiBTC(hyperCrocVault);
        } else if (adapter == Adapter.HyperCrocPoolAdapter) {
            deployedAdapter = _deployHyperCrocPool(hyperCrocVault);
        } else if (adapter == Adapter.HyperCrocVaultAdapter) {
            deployedAdapter = _deployHyperCrocVault();
        } else if (adapter == Adapter.Lido) {
            deployedAdapter = _deployLido();
        } else if (adapter == Adapter.MakerDaoDAI) {
            deployedAdapter = _deployMakerDaoDai();
        } else if (adapter == Adapter.MakerDaoUSDS) {
            deployedAdapter = _deployMakerDaoUsds();
        } else if (adapter == Adapter.Morpho) {
            deployedAdapter = _deployMorpho();
        } else if (adapter == Adapter.MorphoV1_1) {
            deployedAdapter = _deployMorphoV1_1();
        } else if (adapter == Adapter.PendleAdapter) {
            deployedAdapter = _deployPendle();
        } else if (adapter == Adapter.ResolvAdapter) {
            deployedAdapter = _deployResolv();
        } else if (adapter == Adapter.UniswapAdapter) {
            deployedAdapter = _deployUniswap();
        }

        if (deployedAdapter == address(0)) {
            revert("Adapter not supported");
        }

        _saveDeployment(adapter, deployedAdapter, hyperCrocVault);
    }

    function _deployAave() internal returns (address) {
        address aavePoolAddressProvider = getAddress("AavePoolAddressProvider");

        vm.broadcast();
        AaveAdapter aaveAdapter = new AaveAdapter(aavePoolAddressProvider);
        return address(aaveAdapter);
    }

    function _deployResolv() internal returns (address) {
        address wstUSR = getAddress("wstUSR");

        vm.broadcast();
        ResolvAdapter resolvAdapter = new ResolvAdapter(wstUSR);
        return address(resolvAdapter);
    }

    function _deployCurveRouter() internal returns (address) {
        address curveRouter = getAddress("CurveRouterV1_2");

        vm.broadcast();
        CurveRouterAdapter curveRouterAdapter = new CurveRouterAdapter(curveRouter);
        return address(curveRouterAdapter);
    }


    function _deployEthena(address hyperCrocVault) internal returns (address) {
        address sUsde = getAddress("sUSDE");

        vm.broadcast();
        EthenaAdapter ethenaAdapter = new EthenaAdapter(hyperCrocVault, sUsde);
        return address(ethenaAdapter);
    }

    function _deployEtherfiETH() internal returns (address) {
        address weth = getAddress("WETH");
        address weeth = getAddress("weETH");
        address etherfiLiquidityPool = getAddress("EtherFiLiquidityPool");

        vm.broadcast();
        EtherfiETHAdapter etherfiETHAdapter = new EtherfiETHAdapter(weth, weeth, etherfiLiquidityPool);
        return address(etherfiETHAdapter);
    }

    function _deployEtherfiBTC(address hyperCrocVault) internal returns (address) {
        address wbtc = getAddress("WBTC");
        address ebtc = getAddress("eBTC");
        address teller = getAddress("EtherFiBtcTeller");
        address atomicQueue = getAddress("EtherFiBtcAtomicQueue");

        vm.broadcast();
        EtherfiBTCAdapter etherfiBTCAdapter = new EtherfiBTCAdapter(hyperCrocVault, wbtc, ebtc, teller, atomicQueue);
        return address(etherfiBTCAdapter);
    }

    function _deployHyperCrocVault() internal returns (address) {
        address hyperCrocVaultFactory = getAddress("HyperCrocVaultFactory");

        vm.broadcast();
        HyperCrocVaultAdapter hyperCrocVaultAdapter = new HyperCrocVaultAdapter(hyperCrocVaultFactory);
        return address(hyperCrocVaultAdapter);
    }

    function _deployHyperCrocPool(address hyperCrocVault) internal returns (address) {
        vm.broadcast();
        HyperCrocPoolAdapter hyperCrocPoolAdapter = new HyperCrocPoolAdapter(hyperCrocVault);
        return address(hyperCrocPoolAdapter);
    }

    function _deployLido() internal returns (address) {
        address weth = getAddress("WETH");
        address wsteth = getAddress("wstETH");
        address lidoWithdrawalQueue = getAddress("LidoWithdrawalQueue");

        vm.broadcast();
        LidoAdapter lidoAdapter = new LidoAdapter(weth, wsteth, lidoWithdrawalQueue);
        return address(lidoAdapter);
    }

    function _deployMakerDaoDai() internal returns (address) {
        address sdai = getAddress("sDAI");

        vm.broadcast();
        MakerDaoDaiAdapter makerDaoDAIAdapter = new MakerDaoDaiAdapter(sdai);
        return address(makerDaoDAIAdapter);
    }

    function _deployMakerDaoUsds() internal returns (address) {
        address susds = getAddress("sUSDS");

        vm.broadcast();
        MakerDaoUsdsAdapter makerDaoDAIAdapter = new MakerDaoUsdsAdapter(susds);
        return address(makerDaoDAIAdapter);
    }

    function _deployMorpho() internal returns (address) {
        address morphoFactory = getAddress("MetaMorphoFactory");

        vm.broadcast();
        MorphoAdapter morphoAdapter = new MorphoAdapter(morphoFactory);
        return address(morphoAdapter);
    }

    function _deployMorphoV1_1() internal returns (address) {
        address morphoFactoryV1_1 = getAddress("MetaMorphoFactoryV1_1");

        vm.broadcast();
        MorphoAdapterV1_1 morphoAdapter = new MorphoAdapterV1_1(morphoFactoryV1_1);
        return address(morphoAdapter);
    }

    function _deployPendle() internal returns (address) {
        address pendleRouter = getAddress("PendleRouter");

        vm.broadcast();
        PendleAdapter pendleAdapter = new PendleAdapter(pendleRouter);
        return address(pendleAdapter);
    }

    function _deployUniswap() internal returns (address) {
        address uniswapV3Router = getAddress("UniswapV3Router");
        address universalRouter = getAddress("UniversalRouter");
        address permit2 = getAddress("UniswapPermit2");

        vm.broadcast();
        UniswapAdapter uniswapAdapter = new UniswapAdapter(uniswapV3Router, universalRouter, permit2);
        return address(uniswapAdapter);
    }

    function _saveDeployment(Adapter adapter, address adapterAddress, address hyperCrocVault) internal {
        string memory path = _getDeploymentPath(DEPLOYMENT_FILE);
        if (!vm.exists(path)) {
            _createEmptyDeploymentFile(path);
        }

        string memory deploymentKey = _getAdapterName(adapter);
        if (_isPerVaultAdapter(adapter)) {
            deploymentKey = string.concat(deploymentKey, "_", vm.toString(hyperCrocVault));
        }
        _saveInDeploymentFile(path, deploymentKey, adapterAddress);
    }
}
