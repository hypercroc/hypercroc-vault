// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

import {HyperCrocVaultFactory} from "../../contracts/HyperCrocVaultFactory.sol";
import {HyperCrocVault} from "../../contracts/HyperCrocVault.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";
import {AaveAdapter} from "../../contracts/adapters/aave/AaveAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

contract AaveAdapterTest is Test {
    uint256 public constant FORK_BLOCK = 22515980;

    IPoolAddressesProvider private constant AAVE_POOL_PROVIDER =
        IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 private aUsdc;
    IERC20 private aUsdt;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    AaveAdapter private adapter;
    HyperCrocVault private hyperCrocVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        aUsdc = IERC20(IPool(AAVE_POOL_PROVIDER.getPool()).getReserveData(address(USDC)).aTokenAddress);
        aUsdt = IERC20(IPool(AAVE_POOL_PROVIDER.getPool()).getReserveData(address(USDT)).aTokenAddress);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(USDT), address(USDC));
        oracle.setPrice(oracle.ONE(), address(aUsdc), address(USDC));
        oracle.setPrice(oracle.ONE(), address(aUsdt), address(USDC));

        address hyperCrocVaultImplementation = address(new HyperCrocVault());
        address withdrawalQueueImplementation = address(new WithdrawalQueue());
        address hyperCrocVaultFactoryImplementation = address(new HyperCrocVaultFactory());

        bytes memory data = abi.encodeWithSelector(
            HyperCrocVaultFactory.initialize.selector, hyperCrocVaultImplementation, withdrawalQueueImplementation
        );
        ERC1967Proxy hyperCrocVaultFactoryProxy = new ERC1967Proxy(hyperCrocVaultFactoryImplementation, data);
        HyperCrocVaultFactory hyperCrocVaultFactory = HyperCrocVaultFactory(address(hyperCrocVaultFactoryProxy));

        (address deployedVault,) = hyperCrocVaultFactory.deployVault(
            address(USDC),
            "lpName",
            "lpSymbol",
            "withdrawalQueueName",
            "withdrawalQueueSymbol",
            address(0xFEE),
            address(oracle)
        );

        hyperCrocVault = HyperCrocVault(deployedVault);
        hyperCrocVault.setMaxTrackedAssets(type(uint8).max);

        adapter = new AaveAdapter(address(AAVE_POOL_PROVIDER));
        hyperCrocVault.addAdapter(address(adapter));
        assertEq(hyperCrocVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(USDC), address(hyperCrocVault), 10 ** 12);
        deal(address(USDT), address(hyperCrocVault), 10 ** 12);

        hyperCrocVault.addTrackedAsset(address(USDT));
        hyperCrocVault.addTrackedAsset(address(aUsdc));
    }

    function testSupply() public {
        uint256 usdcBalanceBefore = USDC.balanceOf(address(hyperCrocVault));
        uint256 supplyAmount = 1000 * 10 ** 6;
        vm.prank(address(hyperCrocVault));
        adapter.supply(address(USDC), supplyAmount);

        assertEq(usdcBalanceBefore - USDC.balanceOf(address(hyperCrocVault)), supplyAmount);
        assertApproxEqAbs(aUsdc.balanceOf(address(hyperCrocVault)), supplyAmount, 1);
        assertEq(aUsdc.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testSupplyAllExcept() public {
        uint256 usdcBalanceBefore = USDC.balanceOf(address(hyperCrocVault));
        uint256 exceptAmount = 1000 * 10 ** 6;
        vm.prank(address(hyperCrocVault));
        adapter.supplyAllExcept(address(USDC), exceptAmount);

        assertEq(USDC.balanceOf(address(hyperCrocVault)), exceptAmount);
        assertApproxEqAbs(aUsdc.balanceOf(address(hyperCrocVault)), usdcBalanceBefore - exceptAmount, 1);
        assertEq(aUsdc.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testFullWithdraw() public {
        uint256 usdcBalanceBefore = USDC.balanceOf(address(hyperCrocVault));
        uint256 supplyAmount = 1000 * 10 ** 6;
        vm.prank(address(hyperCrocVault));
        adapter.supply(address(USDC), supplyAmount);

        vm.prank(address(hyperCrocVault));
        adapter.withdraw(address(USDC), type(uint256).max);

        assertApproxEqAbs(usdcBalanceBefore, USDC.balanceOf(address(hyperCrocVault)), 1);
        assertEq(aUsdc.balanceOf(address(hyperCrocVault)), 0);
        assertEq(aUsdc.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testPartialWithdraw() public {
        uint256 usdcBalanceBefore = USDC.balanceOf(address(hyperCrocVault));
        uint256 supplyAmount = 1000 * 10 ** 6;
        vm.prank(address(hyperCrocVault));
        adapter.supply(address(USDC), supplyAmount);

        uint256 aTokenBalanceBefore = aUsdc.balanceOf(address(hyperCrocVault));
        uint256 withdrawalAmount = aTokenBalanceBefore / 2;
        vm.prank(address(hyperCrocVault));
        adapter.withdraw(address(USDC), withdrawalAmount);

        assertApproxEqAbs(
            usdcBalanceBefore - (aTokenBalanceBefore - withdrawalAmount), USDC.balanceOf(address(hyperCrocVault)), 1
        );
        assertApproxEqAbs(aUsdc.balanceOf(address(hyperCrocVault)), aTokenBalanceBefore - withdrawalAmount, 1);
        assertEq(aUsdc.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testWithdrawAllExcept() public {
        uint256 usdcBalanceBefore = USDC.balanceOf(address(hyperCrocVault));
        uint256 supplyAmount = 1000 * 10 ** 6;
        vm.prank(address(hyperCrocVault));
        adapter.supply(address(USDC), supplyAmount);

        vm.prank(address(hyperCrocVault));
        uint256 exceptAmount = 10 * 10 ** 6;
        adapter.withdrawAllExcept(address(USDC), exceptAmount);

        assertApproxEqAbs(usdcBalanceBefore, USDC.balanceOf(address(hyperCrocVault)) + exceptAmount, 1);
        assertApproxEqAbs(aUsdc.balanceOf(address(hyperCrocVault)), exceptAmount, 1);
        assertEq(aUsdc.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }
}
