// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {HyperCrocVaultFactory} from "../../contracts/HyperCrocVaultFactory.sol";
import {HyperCrocVault} from "../../contracts/HyperCrocVault.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";
import {LiminalAdapter} from "../../contracts/adapters/liminal/LiminalAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";
import {Asserts} from "../../contracts/libraries/Asserts.sol";
import {IExternalPositionAdapter} from "../../contracts/interfaces/IExternalPositionAdapter.sol";
import {IAdapter} from "../../contracts/interfaces/IAdapter.sol";

contract LiminalAdapterTest is Test {
    string private mainnetRpcUrl = vm.envString("HYPER_RPC_URL");

    IERC20 private constant USDT = IERC20(0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb);
    IERC20 private constant USDC = IERC20(0xb88339CB7199b77E23DB6E890353E22632Ba630f);
    IERC20 private constant XHYPE = IERC20(0xAc962FA04BF91B7fd0DC0c5C32414E0Ce3C51E03);

    address private constant DepositPipe = 0xe2d9598D5FeDb9E4044D50510AabA68B095f2Ab2;
    address private constant RedemptionPipe = 0x19f4881cdB479d01cE214F6908c99b4fe76C03e8;

    LiminalAdapter private adapter;
    HyperCrocVault private hyperCrocVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl));

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(USDC), address(USDT));
        oracle.setPrice(oracle.ONE(), address(XHYPE), address(USDT));

        address hyperCrocVaultImplementation = address(new HyperCrocVault());
        address withdrawalQueueImplementation = address(new WithdrawalQueue());
        address hyperCrocVaultFactoryImplementation = address(new HyperCrocVaultFactory());

        bytes memory data = abi.encodeWithSelector(
            HyperCrocVaultFactory.initialize.selector, hyperCrocVaultImplementation, withdrawalQueueImplementation
        );
        ERC1967Proxy hyperCrocVaultFactoryProxy = new ERC1967Proxy(hyperCrocVaultFactoryImplementation, data);
        HyperCrocVaultFactory hyperCrocVaultFactory = HyperCrocVaultFactory(address(hyperCrocVaultFactoryProxy));

        (address deployedVault,) = hyperCrocVaultFactory.deployVault(
            address(USDT),
            "lpName",
            "lpSymbol",
            "withdrawalQueueName",
            "withdrawalQueueSymbol",
            address(0xFEE),
            address(oracle)
        );

        hyperCrocVault = HyperCrocVault(deployedVault);
        hyperCrocVault.setMaxExternalPositionAdapters(type(uint8).max);
        hyperCrocVault.setMaxTrackedAssets(type(uint8).max);

        adapter = new LiminalAdapter(address(USDC), address(XHYPE), DepositPipe, RedemptionPipe);
        hyperCrocVault.addAdapter(address(adapter));
        assertEq(hyperCrocVault.externalPositionAdapterPosition(address(adapter)), 0);

        hyperCrocVault.addTrackedAsset(address(USDC));
        hyperCrocVault.addTrackedAsset(address(XHYPE));
    }

    function test_constructor() public {
        vm.expectRevert(Asserts.ZeroAddress.selector);
        new LiminalAdapter(address(0), address(1), address(1), address(1));

        vm.expectRevert(Asserts.ZeroAddress.selector);
        new LiminalAdapter(address(USDC), address(0), address(1), address(1));

        vm.expectRevert(Asserts.ZeroAddress.selector);
        new LiminalAdapter(address(USDC), address(XHYPE), address(0), address(1));

        vm.expectRevert(Asserts.ZeroAddress.selector);
        new LiminalAdapter(address(USDC), address(XHYPE), DepositPipe, address(0));

        LiminalAdapter _adapter = new LiminalAdapter(address(USDC), address(XHYPE), DepositPipe, RedemptionPipe);
        assertEq(address(_adapter.getUSDC()), address(USDC));
        assertEq(address(_adapter.getDepositAsset()), address(USDT));
        assertEq(address(_adapter.getXHYPE()), address(XHYPE));
        assertEq(address(_adapter.getLiminalDepositPipe()), DepositPipe);
        assertEq(address(_adapter.getLiminalRedemptionPipe()), RedemptionPipe);
    }

    function test_supportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IAdapter).interfaceId));
    }

    function test_deposit() public {
        uint256 amount = 10_000 * 10 ** 6;

        deal(address(USDT), address(hyperCrocVault), amount);
        vm.prank(address(hyperCrocVault));
        uint256 output = adapter.deposit(amount, 0);
        assertNotEq(output, 0);

        assertEq(XHYPE.balanceOf(address(hyperCrocVault)), output);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), 0);
        assertEq(XHYPE.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);
    }

    function test_depositAllExcept() public {
        uint256 kHYPEBalanceBefore = XHYPE.balanceOf(address(hyperCrocVault));
        uint256 except = 10_000 * 10 ** 6;
        uint256 initialAmount = 15_000 * 10 ** 6;

        deal(address(USDT), address(hyperCrocVault), initialAmount);
        vm.prank(address(hyperCrocVault));
        uint256 output = adapter.depositAllExcept(except, 0);
        assertNotEq(output, 0);

        assertEq(XHYPE.balanceOf(address(hyperCrocVault)), kHYPEBalanceBefore + output);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), except);
        assertEq(XHYPE.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);
    }

    function test_redeem() public {
        uint256 amount = 5 ether;
        deal(address(XHYPE), address(hyperCrocVault), amount);

        vm.prank(address(hyperCrocVault));
        uint256 output = adapter.redeem(amount);

        assertEq(XHYPE.balanceOf(address(hyperCrocVault)),0);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), 0);
        assertEq(USDC.balanceOf(address(hyperCrocVault)), output);
        assertEq(XHYPE.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    // function test_requestWithdrawalAllExcept() public {
    //     uint256 amount = 5 ether;
    //     deal(address(WHYPE), address(hyperCrocVault), amount);
    //     vm.startPrank(address(hyperCrocVault));
    //     adapter.stake(amount);

    //     uint256 kHYPEBalance = KHYPE.balanceOf(address(hyperCrocVault));

    //     uint256 expectedRequestId = StakingManager.nextWithdrawalId(address(adapter));
    //     uint256 exceptAmount = 3 ether;
    //     uint256 withdrawalAmount = kHYPEBalance - exceptAmount;

    //     vm.expectEmit(true, true, false, false);
    //     emit KinetiqAdapter.KinetiqWithdrawalRequested(address(hyperCrocVault), expectedRequestId, withdrawalAmount);
    //     adapter.requestWithdrawalAllExcept(exceptAmount);

    //     uint256 requestId = StakingManager.nextWithdrawalId(address(adapter)) - 1;
    //     IStakingManager.WithdrawalRequest memory request =
    //         StakingManager.withdrawalRequests(address(adapter), requestId);
    //     assertNotEq(request.hypeAmount, 0);

    //     (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
    //     assertEq(assets.length, 1);
    //     assertEq(assets[0], address(WHYPE));
    //     assertEq(amounts.length, 1);
    //     assertEq(amounts[0], request.hypeAmount);

    //     (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
    //     assertEq(debtAssets.length, 0);
    //     assertEq(debtAmounts.length, 0);

    //     assertEq(adapter.getWithdrawalQueueStart(address(hyperCrocVault)), 0);
    //     assertEq(adapter.getWithdrawalQueueEnd(address(hyperCrocVault)), 1);
    //     assertEq(adapter.getWithdrawalQueueRequest(address(hyperCrocVault), 0), requestId);
    // }

    // function test_claimWithdrawal1() public {
    //     assertFalse(adapter.isClaimable(address(hyperCrocVault)));

    //     uint256 amount = 5 ether;
    //     deal(address(WHYPE), address(hyperCrocVault), amount);
    //     vm.startPrank(address(hyperCrocVault));
    //     adapter.stake(amount);
    //     uint256 withdrawalAmount = 2 ether;
    //     adapter.requestWithdrawal(withdrawalAmount);
    //     vm.stopPrank();

    //     assertFalse(adapter.isClaimable(address(hyperCrocVault)));

    //     uint256 start = block.timestamp;
    //     vm.warp(start + StakingManager.withdrawalDelay());

    //     assertTrue(adapter.isClaimable(address(hyperCrocVault)));

    //     uint256 balanceBefore = WHYPE.balanceOf(address(hyperCrocVault));

    //     vm.expectEmit(true, true, false, false);
    //     emit KinetiqAdapter.KinetiqWithdrawalClaimed(
    //         address(hyperCrocVault), StakingManager.nextWithdrawalId(address(adapter)) - 1, withdrawalAmount
    //     );
    //     vm.prank(address(hyperCrocVault));
    //     adapter.claimWithdrawal();

    //     assertTrue(WHYPE.balanceOf(address(hyperCrocVault)) > balanceBefore);

    //     (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
    //     assertEq(assets.length, 0);
    //     assertEq(amounts.length, 0);
    // }

    // function test_claimWithdrawalShouldFailWhenQueueIsEmpty() public {
    //     vm.prank(address(hyperCrocVault));
    //     vm.expectRevert(abi.encodeWithSelector(KinetiqAdapter.KinetiqAdapter__NoWithdrawRequestInQueue.selector));
    //     adapter.claimWithdrawal();
    // }

    // function test_getDebtAssets() public view {
    //     (address[] memory assets, uint256[] memory amounts) = adapter.getDebtAssets();
    //     assertEq(assets.length, 0);
    //     assertEq(amounts.length, 0);
    // }

    // function test_getManagedAssets() public {
    //     (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets(address(hyperCrocVault));
    //     assertEq(assets.length, 0);
    //     assertEq(amounts.length, 0);

    //     uint256 amount = 5 ether;
    //     deal(address(WHYPE), address(hyperCrocVault), amount);
    //     vm.startPrank(address(hyperCrocVault));
    //     adapter.stake(amount);
    //     uint256 withdrawalAmount = 2 ether;
    //     adapter.requestWithdrawal(withdrawalAmount);

    //     (assets, amounts) = adapter.getManagedAssets(address(hyperCrocVault));
    //     assertEq(assets.length, 1);
    //     assertEq(amounts.length, 1);
    // }

    // function test_getWithdrawalQueueRequestShouldFailWhenEmptyQueue() public {
    //     vm.expectRevert(abi.encodeWithSelector(KinetiqAdapter.KinetiqAdapter__NoWithdrawRequestInQueue.selector));
    //     adapter.getWithdrawalQueueRequest(address(hyperCrocVault), 0);
    // }

    // function test_receive() public {
    //     address user = address(0x123);
    //     uint256 amount = 1 ether;
    //     vm.deal(user, amount);
    //     vm.startPrank(user);
    //     (bool success,) = address(adapter).call{value: amount}("");
    //     assertTrue(success);
    // }
}
