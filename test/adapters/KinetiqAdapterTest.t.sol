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
import {KinetiqAdapter} from "../../contracts/adapters/kinetiq/KinetiqAdapter.sol";
import {IStakingManager} from "../../contracts/adapters/kinetiq/interfaces/IStakingManager.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";
import {Asserts} from "../../contracts/libraries/Asserts.sol";
import {IExternalPositionAdapter} from "../../contracts/interfaces/IExternalPositionAdapter.sol";
import {IAdapter} from "../../contracts/interfaces/IAdapter.sol";

contract KinetiqAdapterTest is Test {
    string private mainnetRpcUrl = vm.envString("HYPER_RPC_URL");

    IERC20 private constant USDT = IERC20(0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb);
    IERC20 private constant WHYPE = IERC20(0x5555555555555555555555555555555555555555);
    IERC20 private constant KHYPE = IERC20(0xfD739d4e423301CE9385c1fb8850539D657C296D);

    IStakingManager private constant StakingManager =
        IStakingManager(0x393D0B87Ed38fc779FD9611144aE649BA6082109);

    KinetiqAdapter private adapter;
    HyperCrocVault private hyperCrocVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl));

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(WHYPE), address(USDT));
        oracle.setPrice(oracle.ONE(), address(KHYPE), address(USDT));

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

        adapter = new KinetiqAdapter(address(WHYPE), address(StakingManager));
        hyperCrocVault.addAdapter(address(adapter));
        assertEq(hyperCrocVault.externalPositionAdapterPosition(address(adapter)), 1);

        hyperCrocVault.addTrackedAsset(address(WHYPE));
        hyperCrocVault.addTrackedAsset(address(KHYPE));
    }

    function test_constructor() public {
        vm.expectRevert(Asserts.ZeroAddress.selector);
        new KinetiqAdapter(address(0), address(1));

        vm.expectRevert(Asserts.ZeroAddress.selector);
        new KinetiqAdapter(address(WHYPE), address(0));

        KinetiqAdapter _adapter = new KinetiqAdapter(address(WHYPE), address(StakingManager));
        assertEq(address(_adapter.getWHYPE()), address(WHYPE));
        assertEq(address(_adapter.getKHYPE()), address(KHYPE));
        assertEq(address(_adapter.getKinetiqStakingManager()), address(StakingManager));
    }

    function test_supportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IAdapter).interfaceId));
        assertTrue(adapter.supportsInterface(type(IExternalPositionAdapter).interfaceId));
    }

    function test_stake() public {
        uint256 amount = 5 ether;

        deal(address(WHYPE), address(hyperCrocVault), amount);
        vm.prank(address(hyperCrocVault));
        adapter.stake(amount);

        assertTrue(KHYPE.balanceOf(address(hyperCrocVault)) > 0);
        assertEq(WHYPE.balanceOf(address(hyperCrocVault)), 0);
        assertEq(KHYPE.balanceOf(address(adapter)), 0);
        assertEq(WHYPE.balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }

    function test_stakeAllExcept() public {
        uint256 kHYPEBalanceBefore = KHYPE.balanceOf(address(hyperCrocVault));
        uint256 except = 5 ether;
        uint256 initialAmount = 15 ether;

        deal(address(WHYPE), address(hyperCrocVault), initialAmount);
        vm.prank(address(hyperCrocVault));
        adapter.stakeAllExcept(except);

        assertGt(KHYPE.balanceOf(address(hyperCrocVault)), kHYPEBalanceBefore);
        assertEq(WHYPE.balanceOf(address(hyperCrocVault)), except);
        assertEq(KHYPE.balanceOf(address(adapter)), 0);
        assertEq(WHYPE.balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }

    function test_requestWithdrawal() public {
        uint256 amount = 5 ether;
        deal(address(WHYPE), address(hyperCrocVault), amount);
        vm.startPrank(address(hyperCrocVault));
        adapter.stake(amount);

        uint256 expectedRequestId = StakingManager.nextWithdrawalId(address(adapter));
        uint256 withdrawalAmount = 2 ether;
        vm.expectEmit(true, true, false, false);
        emit KinetiqAdapter.KinetiqWithdrawalRequested(address(hyperCrocVault), expectedRequestId, withdrawalAmount);
        adapter.requestWithdrawal(withdrawalAmount);

        uint256 requestId = StakingManager.nextWithdrawalId(address(adapter)) - 1;
        IStakingManager.WithdrawalRequest memory request =
            StakingManager.withdrawalRequests(address(adapter), requestId);
        assertNotEq(request.hypeAmount, 0);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(WHYPE));
        assertEq(amounts.length, 1);
        assertEq(amounts[0], request.hypeAmount);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 0);
        assertEq(debtAmounts.length, 0);

        assertEq(adapter.getWithdrawalQueueStart(address(hyperCrocVault)), 0);
        assertEq(adapter.getWithdrawalQueueEnd(address(hyperCrocVault)), 1);
        assertEq(adapter.getWithdrawalQueueRequest(address(hyperCrocVault), 0), requestId);
    }

    function test_requestWithdrawalAllExcept() public {
        uint256 amount = 5 ether;
        deal(address(WHYPE), address(hyperCrocVault), amount);
        vm.startPrank(address(hyperCrocVault));
        adapter.stake(amount);

        uint256 kHYPEBalance = KHYPE.balanceOf(address(hyperCrocVault));

        uint256 expectedRequestId = StakingManager.nextWithdrawalId(address(adapter));
        uint256 exceptAmount = 3 ether;
        uint256 withdrawalAmount = kHYPEBalance - exceptAmount;

        vm.expectEmit(true, true, false, false);
        emit KinetiqAdapter.KinetiqWithdrawalRequested(address(hyperCrocVault), expectedRequestId, withdrawalAmount);
        adapter.requestWithdrawalAllExcept(exceptAmount);

        uint256 requestId = StakingManager.nextWithdrawalId(address(adapter)) - 1;
        IStakingManager.WithdrawalRequest memory request =
            StakingManager.withdrawalRequests(address(adapter), requestId);
        assertNotEq(request.hypeAmount, 0);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(WHYPE));
        assertEq(amounts.length, 1);
        assertEq(amounts[0], request.hypeAmount);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 0);
        assertEq(debtAmounts.length, 0);

        assertEq(adapter.getWithdrawalQueueStart(address(hyperCrocVault)), 0);
        assertEq(adapter.getWithdrawalQueueEnd(address(hyperCrocVault)), 1);
        assertEq(adapter.getWithdrawalQueueRequest(address(hyperCrocVault), 0), requestId);
    }

    function test_claimWithdrawal1() public {
        assertFalse(adapter.isClaimable(address(hyperCrocVault)));

        uint256 amount = 5 ether;
        deal(address(WHYPE), address(hyperCrocVault), amount);
        vm.startPrank(address(hyperCrocVault));
        adapter.stake(amount);
        uint256 withdrawalAmount = 2 ether;
        adapter.requestWithdrawal(withdrawalAmount);
        vm.stopPrank();

        assertFalse(adapter.isClaimable(address(hyperCrocVault)));

        uint256 start = block.timestamp;
        vm.warp(start + StakingManager.withdrawalDelay());

        assertTrue(adapter.isClaimable(address(hyperCrocVault)));

        uint256 balanceBefore = WHYPE.balanceOf(address(hyperCrocVault));

        vm.expectEmit(true, true, false, false);
        emit KinetiqAdapter.KinetiqWithdrawalClaimed(
            address(hyperCrocVault), StakingManager.nextWithdrawalId(address(adapter)) - 1, withdrawalAmount
        );
        vm.prank(address(hyperCrocVault));
        adapter.claimWithdrawal();

        assertTrue(WHYPE.balanceOf(address(hyperCrocVault)) > balanceBefore);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }

    function test_claimWithdrawalShouldFailWhenQueueIsEmpty() public {
        vm.prank(address(hyperCrocVault));
        vm.expectRevert(abi.encodeWithSelector(KinetiqAdapter.KinetiqAdapter__NoWithdrawRequestInQueue.selector));
        adapter.claimWithdrawal();
    }

    function test_getDebtAssets() public view {
        (address[] memory assets, uint256[] memory amounts) = adapter.getDebtAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }

    function test_getManagedAssets() public {
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets(address(hyperCrocVault));
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);

        uint256 amount = 5 ether;
        deal(address(WHYPE), address(hyperCrocVault), amount);
        vm.startPrank(address(hyperCrocVault));
        adapter.stake(amount);
        uint256 withdrawalAmount = 2 ether;
        adapter.requestWithdrawal(withdrawalAmount);

        (assets, amounts) = adapter.getManagedAssets(address(hyperCrocVault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
    }

    function test_getWithdrawalQueueRequestShouldFailWhenEmptyQueue() public {
        vm.expectRevert(abi.encodeWithSelector(KinetiqAdapter.KinetiqAdapter__NoWithdrawRequestInQueue.selector));
        adapter.getWithdrawalQueueRequest(address(hyperCrocVault), 0);
    }

    function test_receive() public {
        address user = address(0x123);
        uint256 amount = 1 ether;
        vm.deal(user, amount);
        vm.startPrank(user);
        (bool success,) = address(adapter).call{value: amount}("");
        assertTrue(success);
    }
}
