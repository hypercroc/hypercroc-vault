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
import {HyperbeatAdapter} from "../../contracts/adapters/hyperbeat/HyperbeatAdapter.sol";
import {IWithdrawalQueue} from "../../contracts/adapters/hyperbeat/interfaces/IWithdrawalQueue.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";
import {Asserts} from "../../contracts/libraries/Asserts.sol";
import {IExternalPositionAdapter} from "../../contracts/interfaces/IExternalPositionAdapter.sol";
import {IAdapter} from "../../contracts/interfaces/IAdapter.sol";

contract HyperbeatAdapterTest is Test {
    string private mainnetRpcUrl = vm.envString("HYPER_RPC_URL");

    IERC20 private constant USDT = IERC20(0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb);
    IERC20 private constant HB_USDT = IERC20(0x5e105266db42f78FA814322Bce7f388B4C2e61eb);

    address private constant Depositor = 0x6261F30144B259C74243D5f5D9230941186AC936;
    address private constant HBWithdrawalQueue = 0x240e0b2cb615Ded2FE90fDe265B15988Dc45B1c6;
    address private constant HBAdmin = 0x002bD75C185F335b002b150F8aa4A84D34f9bAB2;

    HyperbeatAdapter private adapter;
    HyperCrocVault private hyperCrocVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl));

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(HB_USDT), address(USDT));

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

        adapter = new HyperbeatAdapter(
            address(hyperCrocVault),
            address(USDT),
            address(HB_USDT),
            Depositor,
            HBWithdrawalQueue
        );
        hyperCrocVault.addAdapter(address(adapter));
        assertEq(hyperCrocVault.externalPositionAdapterPosition(address(adapter)), 1);

        hyperCrocVault.addTrackedAsset(address(HB_USDT));
    }

    function test_constructor() public {
        vm.expectRevert(Asserts.ZeroAddress.selector);
        new HyperbeatAdapter(address(0), address(1), address(1), address(1), address(1));

        vm.expectRevert(Asserts.ZeroAddress.selector);
        new HyperbeatAdapter(address(hyperCrocVault), address(0), address(1), address(1), address(1));

        vm.expectRevert(Asserts.ZeroAddress.selector);
        new HyperbeatAdapter(address(hyperCrocVault), address(USDT), address(0), address(1), address(1));

        vm.expectRevert(Asserts.ZeroAddress.selector);
        new HyperbeatAdapter(address(hyperCrocVault), address(USDT), address(HB_USDT), address(0), address(1));

        vm.expectRevert(Asserts.ZeroAddress.selector);
        new HyperbeatAdapter(address(hyperCrocVault), address(USDT), address(HB_USDT), Depositor, address(0));

        HyperbeatAdapter _adapter = new HyperbeatAdapter(
            address(hyperCrocVault),
            address(USDT),
            address(HB_USDT),
            Depositor,
            HBWithdrawalQueue
        );

        assertEq(address(_adapter.getHyperCrocVault()), address(hyperCrocVault));
        assertEq(address(_adapter.getUSDT()), address(USDT));
        assertEq(address(_adapter.getHbUSDT()), address(HB_USDT));
        assertEq(address(_adapter.getHyperbeatDepositor()), Depositor);
        assertEq(address(_adapter.getHyperbeatWithdrawalQueue()), HBWithdrawalQueue);
    }

    function test_supportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IAdapter).interfaceId));
        assertTrue(adapter.supportsInterface(type(IExternalPositionAdapter).interfaceId));
    }

    function test_deposit() public {
        uint256 amount = 10_000 * 10 ** 6;

        deal(address(USDT), address(hyperCrocVault), amount);
        vm.prank(address(hyperCrocVault));
        uint256 output = adapter.deposit(amount, bytes32(0));
        assertNotEq(output, 0);

        assertEq(HB_USDT.balanceOf(address(hyperCrocVault)), output);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), 0);
        assertEq(HB_USDT.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);

        _assertNoManagedAssets();
        _assertNoDebtAssets();
    }

    function test_depositAllExcept() public {
        uint256 kHYPEBalanceBefore = HB_USDT.balanceOf(address(hyperCrocVault));
        uint256 except = 10_000 * 10 ** 6;
        uint256 initialAmount = 15_000 * 10 ** 6;

        deal(address(USDT), address(hyperCrocVault), initialAmount);
        vm.prank(address(hyperCrocVault));
        uint256 output = adapter.depositAllExcept(except, bytes32(0));
        assertNotEq(output, 0);

        assertEq(HB_USDT.balanceOf(address(hyperCrocVault)), kHYPEBalanceBefore + output);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), except);
        assertEq(HB_USDT.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);

        _assertNoManagedAssets();
        _assertNoDebtAssets();
    }

    function test_instantWithdraw() public {
        uint256 amount = 5_000 * 10 ** 6;
        deal(address(HB_USDT), address(hyperCrocVault), amount);

        vm.prank(address(hyperCrocVault));
        uint256 output = adapter.instantWithdraw(amount);

        assertEq(HB_USDT.balanceOf(address(hyperCrocVault)), 0);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), output);
        assertEq(HB_USDT.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);

        _assertNoManagedAssets();
        _assertNoDebtAssets();
    }

    function test_instantWithdrawAllExcept() public {
        uint256 amount = 5_000 * 10 ** 6;
        uint256 except = 2_000 * 10 ** 6;
        deal(address(HB_USDT), address(hyperCrocVault), amount);

        vm.prank(address(hyperCrocVault));
        uint256 output = adapter.instantWithdrawAllExcept(except);

        assertEq(HB_USDT.balanceOf(address(hyperCrocVault)), except);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), output);
        assertEq(HB_USDT.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);

        _assertNoManagedAssets();
        _assertNoDebtAssets();
    }
    
    function test_requestWithdraw() public {
        uint256 amount = 5_000 * 10 ** 6;
        deal(address(HB_USDT), address(hyperCrocVault), amount);

        uint64 deadline = uint64(block.timestamp + 7 * 86400);

        vm.prank(address(hyperCrocVault));
        adapter.requestWithdrawal(amount, deadline);

        assertEq(HB_USDT.balanceOf(address(hyperCrocVault)), 0);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), 0);
        assertEq(HB_USDT.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);

        (address token, uint256 claimableAmount) = adapter.claimable(address(hyperCrocVault));
        assertEq(token, address(0));
        assertEq(claimableAmount, 0);

        assertEq(adapter.hbUSDTRequested(), amount);
        assertEq(adapter.getQueueStart(), 0);
        assertEq(adapter.getQueueEnd(), 1);

        IWithdrawalQueue.WithdrawalRequest memory request = adapter.getRequest(0);
        assertEq(request.amount, amount);
        assertEq(request.deadline, deadline);
        assertEq(request.user, address(adapter));
        assertEq(request.initiator, address(adapter));
        assertEq(request.minAssetOut, request.baseAssetAmount);

        _assertManagedAssets(amount);
        _assertNoDebtAssets();
    }

    function test_requestWithdrawAllExcept() public {
        uint256 balance = 5_000 * 10 ** 6;
        uint256 except = 2_000 * 10 ** 6;
        deal(address(HB_USDT), address(hyperCrocVault), balance);

        uint64 deadline = uint64(block.timestamp + 7 * 86400);

        vm.prank(address(hyperCrocVault));
        adapter.requestWithdrawalAllExcept(except, deadline);

        uint256 amount = balance - except;

        assertEq(HB_USDT.balanceOf(address(hyperCrocVault)), except);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), 0);
        assertEq(HB_USDT.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);

         (address token, uint256 claimableAmount) = adapter.claimable(address(hyperCrocVault));
        assertEq(token, address(0));
        assertEq(claimableAmount, 0);

        assertEq(adapter.hbUSDTRequested(), amount);
        assertEq(adapter.getQueueStart(), 0);
        assertEq(adapter.getQueueEnd(), 1);

        IWithdrawalQueue.WithdrawalRequest memory request = adapter.getRequest(0);
        assertEq(request.amount, amount);
        assertEq(request.deadline, deadline);
        assertEq(request.user, address(adapter));
        assertEq(request.initiator, address(adapter));
        assertEq(request.minAssetOut, request.baseAssetAmount);

        _assertManagedAssets(amount);
        _assertNoDebtAssets();
    }

    function test_cancelWithdraw() public {
        uint256 amount = 5_000 * 10 ** 6;
        deal(address(HB_USDT), address(hyperCrocVault), amount);

        uint64 deadline = uint64(block.timestamp + 7 * 86400);

        vm.prank(address(hyperCrocVault));
        adapter.requestWithdrawal(amount, deadline);

        vm.warp(deadline + 1);

        vm.prank(address(hyperCrocVault));
        adapter.cancelWithdrawal();

        (address token, uint256 claimableAmount) = adapter.claimable(address(hyperCrocVault));
        assertEq(token, address(0));
        assertEq(claimableAmount, 0);

        assertEq(adapter.hbUSDTRequested(), 0);
        assertEq(adapter.getQueueStart(), 1);
        assertEq(adapter.getQueueEnd(), 1);

        _assertNoManagedAssets();
        _assertNoDebtAssets();
    }

    function test_claimProcessedWithdrawal() public {
        uint256 amount = 5_000 * 10 ** 6;
        deal(address(HB_USDT), address(hyperCrocVault), amount);

        uint64 deadline = uint64(block.timestamp + 7 * 86400);

        vm.prank(address(hyperCrocVault));
        adapter.requestWithdrawal(amount, deadline);

        IWithdrawalQueue.WithdrawalRequest memory request = adapter.getRequest(0);

        _processWithdrawal(request);

        (address token, uint256 claimableAmount) = adapter.claimable(address(hyperCrocVault));
        assertEq(token, address(USDT));
        assertEq(claimableAmount, request.baseAssetAmount);

        vm.prank(address(hyperCrocVault));
        adapter.claimProcessedWithdrawal();

        (token, claimableAmount) = adapter.claimable(address(hyperCrocVault));
        assertEq(token, address(0));
        assertEq(claimableAmount, 0);

        assertEq(HB_USDT.balanceOf(address(hyperCrocVault)), 0);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), request.baseAssetAmount);
        assertEq(HB_USDT.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);

        assertEq(adapter.hbUSDTRequested(), 0);
        assertEq(adapter.getQueueStart(), 1);
        assertEq(adapter.getQueueEnd(), 1);

        _assertNoManagedAssets();
        _assertNoDebtAssets();
    }

    function test_claimRejectedWithdrawal() public {
        uint256 amount = 5_000 * 10 ** 6;
        deal(address(HB_USDT), address(hyperCrocVault), amount);

        uint64 deadline = uint64(block.timestamp + 7 * 86400);

        vm.prank(address(hyperCrocVault));
        adapter.requestWithdrawal(amount, deadline);

        IWithdrawalQueue.WithdrawalRequest memory request = adapter.getRequest(0);

        _rejectWithdrawal(request);

        vm.prank(address(hyperCrocVault));
        adapter.claimRejectedWithdrawal();

        assertEq(HB_USDT.balanceOf(address(hyperCrocVault)), amount);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), 0);
        assertEq(HB_USDT.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);

        assertEq(adapter.hbUSDTRequested(), 0);
        assertEq(adapter.getQueueStart(), 1);
        assertEq(adapter.getQueueEnd(), 1);

        _assertNoManagedAssets();
        _assertNoDebtAssets();
    }

    function test_swapRequestsOrder() public {
        uint256 amount0 = 4_000 * 10 ** 6;
        uint256 amount1 = 6_000 * 10 ** 6;
        deal(address(HB_USDT), address(hyperCrocVault), amount0 + amount1);

        uint64 deadline0 = uint64(block.timestamp + 7 * 86400);
        uint64 deadline1 = uint64(block.timestamp + 2 * 7 * 86400);

        vm.prank(address(hyperCrocVault));
        adapter.requestWithdrawal(amount0, deadline0);

        vm.prank(address(hyperCrocVault));
        adapter.requestWithdrawal(amount1, deadline1);

        IWithdrawalQueue.WithdrawalRequest memory request0 = adapter.getRequest(0);
        IWithdrawalQueue.WithdrawalRequest memory request1 = adapter.getRequest(1);

        vm.prank(address(hyperCrocVault));
        adapter.swapRequestsOrder(0, 1);

        IWithdrawalQueue.WithdrawalRequest memory request0New = adapter.getRequest(0);
        IWithdrawalQueue.WithdrawalRequest memory request1New = adapter.getRequest(1);

        assertEq(request0New.baseAssetAmount, request1.baseAssetAmount);
        assertEq(request0New.amount, request1.amount);
        assertEq(request0New.deadline, request1.deadline);

        assertEq(request1New.baseAssetAmount, request0.baseAssetAmount);
        assertEq(request1New.amount, request0.amount);
        assertEq(request1New.deadline, request0.deadline);
    }

    function testFuzz_onlyVault(address signer) public {
        vm.assume(signer != address(hyperCrocVault));

        uint256 amount = 5 ether;

        vm.prank(address(signer));
        vm.expectRevert(HyperbeatAdapter.NoAccess.selector);
        adapter.deposit(amount, 0);

        vm.prank(address(signer));
        vm.expectRevert(HyperbeatAdapter.NoAccess.selector);
        adapter.depositAllExcept(amount, 0);

        vm.prank(address(signer));
        vm.expectRevert(HyperbeatAdapter.NoAccess.selector);
        adapter.instantWithdraw(amount);

        vm.prank(address(signer));
        vm.expectRevert(HyperbeatAdapter.NoAccess.selector);
        adapter.instantWithdrawAllExcept(amount);

        vm.prank(address(signer));
        vm.expectRevert(HyperbeatAdapter.NoAccess.selector);
        adapter.requestWithdrawal(amount, type(uint64).max);

        vm.prank(address(signer));
        vm.expectRevert(HyperbeatAdapter.NoAccess.selector);
        adapter.requestWithdrawalAllExcept(amount, type(uint64).max);

        vm.prank(address(signer));
        vm.expectRevert(HyperbeatAdapter.NoAccess.selector);
        adapter.claimProcessedWithdrawal();

        vm.prank(address(signer));
        vm.expectRevert(HyperbeatAdapter.NoAccess.selector);
        adapter.claimRejectedWithdrawal();

        vm.prank(address(signer));
        vm.expectRevert(HyperbeatAdapter.NoAccess.selector);
        adapter.cancelWithdrawal();

        vm.prank(address(signer));
        vm.expectRevert(HyperbeatAdapter.NoAccess.selector);
        adapter.swapRequestsOrder(0, 1);
    }

    function _assertManagedAssets(uint256 amount) private {
        vm.prank(address(hyperCrocVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);

        assertEq(assets[0], address(HB_USDT));
        assertEq(amounts[0], amount);

        (assets, amounts) = adapter.getManagedAssets(address(hyperCrocVault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);

        assertEq(assets[0], address(HB_USDT));
        assertEq(amounts[0], amount);
    }

    function _assertNoManagedAssets() private {
        vm.prank(address(hyperCrocVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);

        (assets, amounts) = adapter.getManagedAssets(address(hyperCrocVault));
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }

    function _assertNoDebtAssets() private {
        vm.prank(address(hyperCrocVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getDebtAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }

    function _processWithdrawal(IWithdrawalQueue.WithdrawalRequest memory request) private {
        IWithdrawalQueue.WithdrawalRequest[] memory requests = 
            new IWithdrawalQueue.WithdrawalRequest[](1);
        requests[0] = request;

        vm.prank(HBAdmin);
        IWithdrawalQueue(HBWithdrawalQueue).processWithdrawalRequests(requests);
    }

    function _rejectWithdrawal(IWithdrawalQueue.WithdrawalRequest memory request) private {
        vm.prank(HBAdmin);
        IWithdrawalQueue(HBWithdrawalQueue).rejectWithdrawalRequest(request);
    }
}
