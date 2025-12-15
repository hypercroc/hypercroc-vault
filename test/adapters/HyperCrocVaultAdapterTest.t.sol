// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {HyperCrocVaultAdapter} from "contracts/adapters/hyperCrocVault/HyperCrocVaultAdapter.sol";
import {AdapterBase} from "contracts/adapters/AdapterBase.sol";
import {IHyperCrocPool} from "contracts/adapters/hyperCrocPool/interfaces/IHyperCrocPool.sol";
import {FP96} from "contracts/adapters/hyperCrocPool/FP96.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";
import {HyperCrocVaultFactory} from "contracts/HyperCrocVaultFactory.sol";
import {HyperCrocVault} from "contracts/HyperCrocVault.sol";
import {WithdrawalQueue} from "contracts/WithdrawalQueue.sol";
import {IAdapter} from "contracts/interfaces/IAdapter.sol";
import {IExternalPositionAdapter} from "contracts/interfaces/IExternalPositionAdapter.sol";
import {Asserts} from "contracts/libraries/Asserts.sol";
import {HyperCrocPoolMock} from "../mocks/HyperCrocPoolMock.t.sol";
import {IHyperCrocVault} from "contracts/interfaces/IHyperCrocVault.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";

contract HyperCrocVaultAdapterHarness is HyperCrocVaultAdapter {
    constructor(address hyperCrocVaultFactory) HyperCrocVaultAdapter(hyperCrocVaultFactory) {}

    function exposed_addWithdrawalRequest(address owner, address vault, uint256 requestId, uint256 shares) external {
        _addWithdrawalRequest(owner, vault, requestId, shares);
    }

    function exposed_removeWithdrawalRequest(address owner, address vault, uint256 requestId, uint256 shares)
        external
    {
        _removeWithdrawalRequest(owner, vault, requestId, shares);
    }
}

contract HyperCrocVaultAdapterTest is Test {
    using FP96 for IHyperCrocPool.FixedPoint;
    using Math for uint256;

    uint256 private constant X96_ONE = 2 ** 96;
    uint256 private constant FORK_BLOCK_NUMBER = 22497400;

    IERC20 private WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    HyperCrocVaultAdapter internal adapter;

    HyperCrocVaultFactory private hyperCrocVaultFactory;
    HyperCrocVault internal vault;
    HyperCrocVault internal vault2;

    HyperCrocVault internal investVault1;
    HyperCrocVault internal investVault2;
    EulerRouterMock internal oracle;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK_NUMBER);
        vm.skip(block.chainid != 1, "Only mainnet fork test");

        oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(WETH), address(WETH));

        address hyperCrocVaultImplementation = address(new HyperCrocVault());
        address withdrawalQueueImplementation = address(new WithdrawalQueue());
        address hyperCrocVaultFactoryImplementation = address(new HyperCrocVaultFactory());

        bytes memory data = abi.encodeWithSelector(
            HyperCrocVaultFactory.initialize.selector, hyperCrocVaultImplementation, withdrawalQueueImplementation
        );
        ERC1967Proxy hyperCrocVaultFactoryProxy = new ERC1967Proxy(hyperCrocVaultFactoryImplementation, data);
        hyperCrocVaultFactory = HyperCrocVaultFactory(address(hyperCrocVaultFactoryProxy));

        (address deployedVault,) = hyperCrocVaultFactory.deployVault(
            address(WETH),
            "lpName",
            "lpSymbol",
            "withdrawalQueueName",
            "withdrawalQueueSymbol",
            address(0xFEE),
            address(oracle)
        );

        (address deployedVault2,) = hyperCrocVaultFactory.deployVault(
            address(WETH),
            "lpName",
            "lpSymbol",
            "withdrawalQueueName",
            "withdrawalQueueSymbol",
            address(0xFEE),
            address(oracle)
        );

        vault = HyperCrocVault(deployedVault);
        vault.setMaxExternalPositionAdapters(type(uint8).max);
        vault.setMaxTrackedAssets(type(uint8).max);

        vault2 = HyperCrocVault(deployedVault2);
        vault2.setMaxExternalPositionAdapters(type(uint8).max);
        vault2.setMaxTrackedAssets(type(uint8).max);

        adapter = new HyperCrocVaultAdapter(address(hyperCrocVaultFactoryProxy));
        vault.addAdapter(address(adapter));
        vault2.addAdapter(address(adapter));

        (deployedVault,) = hyperCrocVaultFactory.deployVault(
            address(WETH),
            "lvvaWETH-1",
            "lvvaWETH-1",
            "lvvaWETH-1-withdrawal-queue",
            "lvvaWETH-1-withdrawal-queue",
            address(0xFEE),
            address(oracle)
        );
        investVault1 = HyperCrocVault(deployedVault);

        (deployedVault,) = hyperCrocVaultFactory.deployVault(
            address(WETH),
            "lvvaWETH-2",
            "lvvaWETH-2",
            "lvvaWETH-1-withdrawal-queue",
            "lvvaWETH-1-withdrawal-queue",
            address(0xFEE),
            address(oracle)
        );
        investVault2 = HyperCrocVault(deployedVault);

        oracle.setPrice(oracle.ONE(), address(investVault1), address(WETH));
        oracle.setPrice(oracle.ONE(), address(investVault2), address(WETH));

        vault.addTrackedAsset(address(investVault1));
        vault.addTrackedAsset(address(investVault2));
        vault2.addTrackedAsset(address(investVault1));
        vault2.addTrackedAsset(address(investVault2));

        vm.deal(address(vault), 1 ether);
        deal(address(WETH), address(vault), 10 ether);

        vm.deal(address(vault2), 1 ether);
        deal(address(WETH), address(vault2), 10 ether);
    }

    function test_constructorShouldFailWhenZeroAddress() public {
        vm.expectRevert(Asserts.ZeroAddress.selector);
        new HyperCrocVaultAdapter(address(0));
    }

    function test_deposit() public {
        uint256 depositAmount = 2 ether;
        uint256 wethBalanceBefore = WETH.balanceOf(address(vault));

        vm.prank(address(vault));
        uint256 shares = adapter.deposit(address(investVault1), depositAmount);

        assertEq(investVault1.balanceOf(address(vault)), shares);
        assertEq(WETH.balanceOf(address(vault)), wethBalanceBefore - depositAmount);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(investVault1.balanceOf(address(adapter)), 0);

        _assertNoDebtAssets();
        _assertNoManagedAssets();
    }

    function test_depositAllExcept() public {
        uint256 except = 7 ether;

        vm.prank(address(vault));
        uint256 shares = adapter.depositAllExcept(address(investVault1), except);

        assertEq(investVault1.balanceOf(address(vault)), shares);
        assertEq(WETH.balanceOf(address(vault)), except);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(investVault1.balanceOf(address(adapter)), 0);
    }

    function test_depositShouldFailWhenWrongVaultAddress() public {
        uint256 depositAmount = 2 ether;

        vm.expectRevert(HyperCrocVaultAdapter.HyperCrocVaultAdapter__Forbidden.selector);
        vm.prank(address(vault));
        adapter.deposit(address(vault), depositAmount);
    }

    function test_depositShouldFailWhenNotHyperCrocVault() public {
        vm.expectRevert(HyperCrocVaultAdapter.HyperCrocVaultAdapter__UnknownVault.selector);
        hoax(address(vault));
        address wstUSRVault = 0x1202F5C7b4B9E47a1A484E8B270be34dbbC75055;
        adapter.deposit(address(wstUSRVault), 0);
    }

    function test_requestRedeem() public {
        uint256 depositAmount = 2 ether;
        vm.startPrank(address(vault));
        uint256 shares = adapter.deposit(address(investVault1), depositAmount);

        uint256 redeemAmount = 1 ether;
        address withdrawalQueue = investVault1.withdrawalQueue();
        uint256 expectedRequestId = IWithdrawalQueue(withdrawalQueue).lastRequestId() + 1;

        vm.expectEmit(true, true, true, false);
        emit HyperCrocVaultAdapter.HyperCrocVaultRequestWithdrawal(
            address(vault), address(investVault1), expectedRequestId, redeemAmount
        );
        uint256 requestId = adapter.requestRedeem(address(investVault1), redeemAmount);

        assertEq(requestId, expectedRequestId);
        assertEq(investVault1.balanceOf(address(vault)), shares - redeemAmount);
        assertEq(IERC721(withdrawalQueue).ownerOf(requestId), address(adapter));

        assertFalse(adapter.claimPossible(address(investVault1), requestId));

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(investVault1));
        assertEq(amounts.length, 1);
        assertEq(amounts[0], redeemAmount);

        _assertNoDebtAssets();

        assertEq(redeemAmount, adapter.getPendingWithdrawalsShares(address(vault), address(investVault1)));

        (address[] memory vaultsWithPending) = adapter.getPendingWithdrawalsVaults(address(vault));
        assertEq(vaultsWithPending.length, 1);
        assertEq(vaultsWithPending[0], address(investVault1));
        assertEq(1, adapter.getPendingWithdrawalsVaultPosition(address(vault), address(investVault1)));

        assertTrue(adapter.isRequestIdOwner(address(vault), address(investVault1), requestId));
    }

    function test_requestRedeemManyRequests() public {
        uint256 depositAmount = 2 ether;
        vm.startPrank(address(vault));
        adapter.deposit(address(investVault1), depositAmount);

        uint256 redeemAmount = 0.5 ether;
        address withdrawalQueue = investVault1.withdrawalQueue();

        uint256 requestId1 = adapter.requestRedeem(address(investVault1), redeemAmount);
        uint256 requestId2 = adapter.requestRedeem(address(investVault1), redeemAmount);

        assertEq(IERC721(withdrawalQueue).ownerOf(requestId1), address(adapter));
        assertEq(IERC721(withdrawalQueue).ownerOf(requestId2), address(adapter));
        assertEq(IERC721(withdrawalQueue).balanceOf(address(adapter)), 2);

        assertEq(adapter.claimPossible(address(investVault1), requestId1), false);
        assertEq(adapter.claimPossible(address(investVault1), requestId2), false);

        assertEq(redeemAmount * 2, adapter.getPendingWithdrawalsShares(address(vault), address(investVault1)));

        (address[] memory vaultsWithPending) = adapter.getPendingWithdrawalsVaults(address(vault));
        assertEq(vaultsWithPending.length, 1);
        assertEq(vaultsWithPending[0], address(investVault1));
        assertEq(1, adapter.getPendingWithdrawalsVaultPosition(address(vault), address(investVault1)));
    }

    function test_requestRedeemManyVaults() public {
        uint256 depositAmount1 = 2 ether;
        vm.prank(address(vault));
        adapter.deposit(address(investVault1), depositAmount1);

        uint256 depositAmount2 = 4 ether;
        vm.prank(address(vault));
        adapter.deposit(address(investVault2), depositAmount2);

        uint256 redeemAmount = 0.5 ether;
        address withdrawalQueue1 = investVault1.withdrawalQueue();
        address withdrawalQueue2 = investVault2.withdrawalQueue();

        vm.prank(address(vault));
        uint256 requestId1 = adapter.requestRedeem(address(investVault1), redeemAmount);
        vm.prank(address(vault));
        uint256 requestId2 = adapter.requestRedeem(address(investVault2), redeemAmount);

        assertEq(IERC721(withdrawalQueue1).ownerOf(requestId1), address(adapter));
        assertEq(IERC721(withdrawalQueue2).ownerOf(requestId2), address(adapter));
        assertEq(adapter.claimPossible(address(investVault1), requestId1), false);
        assertEq(adapter.claimPossible(address(investVault1), requestId2), false);

        _assertNoDebtAssets();

        assertEq(redeemAmount, adapter.getPendingWithdrawalsShares(address(vault), address(investVault1)));
        assertEq(redeemAmount, adapter.getPendingWithdrawalsShares(address(vault), address(investVault2)));

        (address[] memory vaultsWithPending) = adapter.getPendingWithdrawalsVaults(address(vault));
        assertEq(vaultsWithPending.length, 2);
        assertEq(vaultsWithPending[0], address(investVault1));
        assertEq(1, adapter.getPendingWithdrawalsVaultPosition(address(vault), address(investVault1)));
        assertEq(vaultsWithPending[1], address(investVault2));
        assertEq(2, adapter.getPendingWithdrawalsVaultPosition(address(vault), address(investVault2)));

        assertTrue(adapter.isRequestIdOwner(address(vault), address(investVault1), requestId1));
        assertTrue(adapter.isRequestIdOwner(address(vault), address(investVault2), requestId2));
        assertFalse(adapter.isRequestIdOwner(address(1), address(investVault1), requestId1));
    }

    function test_requestRedeemAllExcept() public {
        uint256 depositAmount = 2 ether;
        vm.prank(address(vault));
        uint256 shares = adapter.deposit(address(investVault1), depositAmount);

        uint256 except = 0.5 ether;
        uint256 redeemAmount = shares - except;
        address withdrawalQueue = investVault1.withdrawalQueue();
        uint256 expectedRequestId = IWithdrawalQueue(withdrawalQueue).lastRequestId() + 1;

        vm.expectEmit(true, true, true, false);
        emit HyperCrocVaultAdapter.HyperCrocVaultRequestWithdrawal(
            address(vault), address(investVault1), expectedRequestId, redeemAmount
        );
        vm.prank(address(vault));
        uint256 requestId = adapter.requestRedeemAllExcept(address(investVault1), except);

        assertEq(requestId, expectedRequestId);
        assertEq(investVault1.balanceOf(address(vault)), except);
        _assertNoDebtAssets();
    }

    function test_requestRedeemShouldFailWhenNotVault() public {
        vm.expectRevert(HyperCrocVaultAdapter.HyperCrocVaultAdapter__UnknownVault.selector);
        hoax(address(vault));
        adapter.requestRedeem(address(1), 0);
    }

    function test_claimWithdrawalPartial() public {
        //deposit
        uint256 depositAmount = 2 ether;
        vm.prank(address(vault));
        adapter.deposit(address(investVault1), depositAmount);

        //requestRedeem
        uint256 redeemAmount = 1 ether;
        address withdrawalQueue = investVault1.withdrawalQueue();

        vm.prank(address(vault));
        uint256 requestId = adapter.requestRedeem(address(investVault1), redeemAmount);

        _finalizeRequest(withdrawalQueue, requestId);
        assertTrue(adapter.claimPossible(address(investVault1), requestId));

        uint256 wethBalanceBefore = WETH.balanceOf(address(vault));

        // claim
        vm.prank(address(vault));
        vm.expectEmit(true, true, true, false);
        emit HyperCrocVaultAdapter.HyperCrocVaultClaimWithdrawal(address(vault), address(investVault1), requestId, redeemAmount);
        uint256 withdrawalAssets = adapter.claimWithdrawal(address(investVault1), requestId);

        assertEq(withdrawalAssets, redeemAmount);
        assertEq(WETH.balanceOf(address(vault)), wethBalanceBefore + withdrawalAssets);

        _assertNoManagedAssets();
        _assertNoDebtAssets();
    }

    function test_claimWithdrawalFull() public {
        uint256 depositAmount = 2 ether;
        vm.prank(address(vault));
        adapter.deposit(address(investVault1), depositAmount);

        uint256 redeemAmount = 2 ether;
        address withdrawalQueue = investVault1.withdrawalQueue();

        vm.prank(address(vault));
        uint256 requestId = adapter.requestRedeem(address(investVault1), redeemAmount);

        _finalizeRequest(withdrawalQueue, requestId);
        assertTrue(adapter.claimPossible(address(investVault1), requestId));

        uint256 wethBalanceBefore = WETH.balanceOf(address(vault));

        vm.prank(address(vault));
        uint256 withdrawalAssets = adapter.claimWithdrawal(address(investVault1), requestId);
        assertEq(withdrawalAssets, depositAmount);
        assertEq(WETH.balanceOf(address(vault)), wethBalanceBefore + withdrawalAssets);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, requestId));
        adapter.claimPossible(address(investVault1), requestId);

        _assertNoManagedAssets();
        _assertNoDebtAssets();
    }

    function test_claimWithdrawFirstRequestFromTwo() public {
        //deposit
        uint256 depositAmount = 2 ether;
        vm.prank(address(vault));
        adapter.deposit(address(investVault1), depositAmount);
        vm.prank(address(vault));
        adapter.deposit(address(investVault2), depositAmount);

        //request two redeems
        uint256 redeemAmount1 = depositAmount;
        uint256 redeemAmount2 = 0.7 ether;
        address withdrawalQueue1 = investVault1.withdrawalQueue();

        vm.prank(address(vault));
        uint256 requestId1 = adapter.requestRedeem(address(investVault1), redeemAmount1);

        vm.prank(address(vault));
        uint256 requestId2 = adapter.requestRedeem(address(investVault2), redeemAmount2);

        _finalizeRequest(withdrawalQueue1, requestId1);
        assertTrue(adapter.claimPossible(address(investVault1), requestId1));
        assertFalse(adapter.claimPossible(address(investVault2), requestId2));

        // claim first requestId
        vm.prank(address(vault));
        adapter.claimWithdrawal(address(investVault1), requestId1);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets(address(vault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(investVault2));
        assertEq(amounts[0], redeemAmount2);

        _assertNoDebtAssets();
    }

    function test_claimShouldFailWhenUnauthorized() public {
        // deposit
        uint256 depositAmount = 2 ether;
        vm.prank(address(vault));
        adapter.deposit(address(investVault1), depositAmount);

        uint256 depositAmount2 = 4 ether;
        vm.prank(address(vault2));
        adapter.deposit(address(investVault1), depositAmount2);

        // request redeem
        vm.prank(address(vault));
        uint256 requestId1 = adapter.requestRedeem(address(investVault1), depositAmount);

        vm.prank(address(vault2));
        uint256 requestId2 = adapter.requestRedeem(address(investVault1), depositAmount);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets(address(vault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(investVault1));
        assertEq(amounts[0], depositAmount);

        (assets, amounts) = adapter.getManagedAssets(address(vault2));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(investVault1));
        assertEq(amounts[0], depositAmount);

        _finalizeRequest(investVault1.withdrawalQueue(), requestId1);
        _finalizeRequest(investVault1.withdrawalQueue(), requestId2);

        //try to claim requestId1 by vault2
        vm.prank(address(vault2));
        vm.expectRevert(HyperCrocVaultAdapter.HyperCrocVaultAdapter__ClaimUnauthorized.selector);
        adapter.claimWithdrawal(address(investVault1), requestId1);
    }

    function test_claimWithdrawShouldFailWhenNotVault() public {
        vm.expectRevert(HyperCrocVaultAdapter.HyperCrocVaultAdapter__UnknownVault.selector);
        hoax(address(vault));
        adapter.claimWithdrawal(address(1), 0);
    }

    function test_getHyperCrocVaultFactory() public view {
        assertEq(adapter.getHyperCrocVaultFactory(), address(hyperCrocVaultFactory));
    }

    function test_addWithdrawalRequest() public {
        HyperCrocVaultAdapterHarness harness = new HyperCrocVaultAdapterHarness(address(hyperCrocVaultFactory));

        assertEq(harness.getPendingWithdrawalsShares(address(vault), address(investVault1)), 0);

        harness.exposed_addWithdrawalRequest(address(vault), address(investVault1), 0, 1 ether);

        assertEq(harness.getPendingWithdrawalsShares(address(vault), address(investVault1)), 1 ether);
        address[] memory vaults = harness.getPendingWithdrawalsVaults(address(vault));
        assertEq(vaults.length, 1);
        assertEq(vaults[0], address(investVault1));

        assertEq(harness.getPendingWithdrawalsVaultPosition(address(vault), address(investVault1)), 1);
    }

    function test_removeWithdrawalRequest() public {
        HyperCrocVaultAdapterHarness harness = new HyperCrocVaultAdapterHarness(address(hyperCrocVaultFactory));
        harness.exposed_addWithdrawalRequest(address(vault), address(1), 1, 1 ether);
        harness.exposed_addWithdrawalRequest(address(vault), address(2), 2, 0.5 ether);
        harness.exposed_addWithdrawalRequest(address(vault), address(3), 3, 0.5 ether);

        // check position of vaults
        assertEq(harness.getPendingWithdrawalsVaultPosition(address(vault), address(1)), 1);
        assertEq(harness.getPendingWithdrawalsVaultPosition(address(vault), address(2)), 2);
        assertEq(harness.getPendingWithdrawalsVaultPosition(address(vault), address(3)), 3);

        // remove first vault
        harness.exposed_removeWithdrawalRequest(address(vault), address(1), 1, 1 ether);

        // check last in first position
        assertEq(harness.getPendingWithdrawalsVaultPosition(address(vault), address(3)), 1);
        assertEq(harness.getPendingWithdrawalsVaultPosition(address(vault), address(2)), 2);
        assertEq(harness.getPendingWithdrawalsVaultPosition(address(vault), address(1)), 0);
    }

    function test_removeWithdrawalRequestShouldFail() public {
        HyperCrocVaultAdapterHarness harness = new HyperCrocVaultAdapterHarness(address(hyperCrocVaultFactory));

        vm.expectRevert(HyperCrocVaultAdapter.HyperCrocVaultAdapter__NoRequestId.selector);
        harness.exposed_removeWithdrawalRequest(address(vault), address(1), 1, 1 ether);
    }

    function _finalizeRequest(address withdrawalQueue, uint256 requestId) private {
        address finalizer = makeAddr("finalizer");
        IWithdrawalQueue(withdrawalQueue).addFinalizer(finalizer, true);
        vm.prank(finalizer);
        IWithdrawalQueue(withdrawalQueue).finalizeRequests(requestId);
    }

    function _assertNoDebtAssets() private view {
        (address[] memory assets, uint256[] memory amounts) = adapter.getDebtAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }

    function _assertNoManagedAssets() private view {
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }
}
