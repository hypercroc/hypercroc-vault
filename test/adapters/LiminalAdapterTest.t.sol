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
import {IRedemptionPipe} from "../../contracts/adapters/liminal/interfaces/IRedemptionPipe.sol";

contract LiminalAdapterTest is Test {
    string private mainnetRpcUrl = vm.envString("HYPER_RPC_URL");

    IERC20 private constant USDT = IERC20(0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb);
    IERC20 private constant USDC = IERC20(0xb88339CB7199b77E23DB6E890353E22632Ba630f);
    IERC20 private constant XHYPE = IERC20(0xAc962FA04BF91B7fd0DC0c5C32414E0Ce3C51E03);

    address private constant DepositPipe = 0xe2d9598D5FeDb9E4044D50510AabA68B095f2Ab2;
    IRedemptionPipe private constant RedemptionPipe = IRedemptionPipe(0x19f4881cdB479d01cE214F6908c99b4fe76C03e8);
    address private constant ADMIN = 0x56485380BA2Af7581b96E8811a78Dbea4bd7db9A;

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

        adapter = new LiminalAdapter(
            address(hyperCrocVault),
            address(USDC),
            address(XHYPE),
            DepositPipe,
            address(RedemptionPipe)
        );

        hyperCrocVault.addAdapter(address(adapter));
        assertEq(hyperCrocVault.externalPositionAdapterPosition(address(adapter)), 1);

        hyperCrocVault.addTrackedAsset(address(USDC));
        hyperCrocVault.addTrackedAsset(address(XHYPE));
    }

    function test_constructor() public {
        vm.expectRevert(Asserts.ZeroAddress.selector);
        new LiminalAdapter(address(0), address(1), address(1), address(1), address(1));

         vm.expectRevert(Asserts.ZeroAddress.selector);
        new LiminalAdapter(address(hyperCrocVault), address(0), address(1), address(1), address(1));

        vm.expectRevert(Asserts.ZeroAddress.selector);
        new LiminalAdapter(address(hyperCrocVault), address(USDC), address(0), address(1), address(1));

        vm.expectRevert(Asserts.ZeroAddress.selector);
        new LiminalAdapter(address(hyperCrocVault), address(USDC), address(XHYPE), address(0), address(1));

        vm.expectRevert(Asserts.ZeroAddress.selector);
        new LiminalAdapter(address(hyperCrocVault), address(USDC), address(XHYPE), DepositPipe, address(0));

        LiminalAdapter _adapter = new LiminalAdapter(
            address(hyperCrocVault),
            address(USDC),
            address(XHYPE),
            DepositPipe,
            address(RedemptionPipe)
        );

        assertEq(address(_adapter.getHyperCrocVault()), address(hyperCrocVault));
        assertEq(address(_adapter.getUSDC()), address(USDC));
        assertEq(address(_adapter.getDepositAsset()), address(USDT));
        assertEq(address(_adapter.getXHYPE()), address(XHYPE));
        assertEq(address(_adapter.getLiminalDepositPipe()), DepositPipe);
        assertEq(address(_adapter.getLiminalRedemptionPipe()), address(RedemptionPipe));
    }

    function test_supportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IAdapter).interfaceId));
        assertTrue(adapter.supportsInterface(type(IExternalPositionAdapter).interfaceId));
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

        _assertNoManagedAssets();
        _assertNoDebtAssets();
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

        _assertNoManagedAssets();
        _assertNoDebtAssets();
    }

    function test_redeem() public {
        uint256 amount = 5 ether;
        deal(address(XHYPE), address(hyperCrocVault), amount);

        vm.prank(address(hyperCrocVault));
        uint256 output = adapter.redeem(amount);

        assertEq(XHYPE.balanceOf(address(hyperCrocVault)), 0);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), 0);
        assertEq(USDC.balanceOf(address(hyperCrocVault)), output);
        assertEq(XHYPE.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);

        _assertNoManagedAssets();
        _assertNoDebtAssets();
    }

     function test_redeemAllExcept() public {
        uint256 amount = 5 ether;
        uint256 except = 2 ether;
        deal(address(XHYPE), address(hyperCrocVault), amount);

        vm.prank(address(hyperCrocVault));
        uint256 output = adapter.redeemAllExcept(except);

        assertEq(XHYPE.balanceOf(address(hyperCrocVault)),  except);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), 0);
        assertEq(USDC.balanceOf(address(hyperCrocVault)), output);
        assertEq(XHYPE.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);

        _assertNoManagedAssets();
        _assertNoDebtAssets();
    }

    function test_requestRedeem() public {
        uint256 withdrawalAmount = 5 ether;
        deal(address(XHYPE), address(hyperCrocVault), withdrawalAmount);

        vm.prank(address(hyperCrocVault));
        adapter.requestRedeem(withdrawalAmount);

        assertEq(XHYPE.balanceOf(address(hyperCrocVault)), 0);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), 0);
        assertEq(USDC.balanceOf(address(hyperCrocVault)), 0);
        assertEq(XHYPE.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);

        assertEq(RedemptionPipe.pendingRedeemRequest(address(adapter)), withdrawalAmount);

        _assertManagedAssets(withdrawalAmount);
        _assertNoDebtAssets();
    }

    function test_requestRedeemAllExcept() public {
        uint256 balance = 5 ether;
        uint256 except = 2 ether;
        uint256 withdrawalAmount = balance - except;
        deal(address(XHYPE), address(hyperCrocVault), balance);

        vm.prank(address(hyperCrocVault));
        adapter.requestRedeemAllExcept(except);

        assertEq(XHYPE.balanceOf(address(hyperCrocVault)), except);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), 0);
        assertEq(USDC.balanceOf(address(hyperCrocVault)), 0);
        assertEq(XHYPE.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);

        assertEq(RedemptionPipe.pendingRedeemRequest(address(adapter)), withdrawalAmount);

        _assertManagedAssets(withdrawalAmount);
        _assertNoDebtAssets();
    }

    function test_fulfillment() public {
        uint256 withdrawalAmount = 5 ether;
        deal(address(XHYPE), address(hyperCrocVault), withdrawalAmount);

        vm.prank(address(hyperCrocVault));
        adapter.requestRedeem(withdrawalAmount);

        _fulfill(withdrawalAmount);

        assertEq(XHYPE.balanceOf(address(hyperCrocVault)), 0);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), 0);
        assertGt(USDC.balanceOf(address(hyperCrocVault)), 0);
        assertEq(XHYPE.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);

        assertEq(RedemptionPipe.pendingRedeemRequest(address(adapter)), 0);

        _assertNoManagedAssets();
        _assertNoDebtAssets();
    }

    function testFuzz_onlyVault(address signer) public {
        vm.assume(signer != address(hyperCrocVault));

        uint256 amount = 5 ether;

        vm.prank(address(signer));
        vm.expectRevert(LiminalAdapter.NoAccess.selector);
        adapter.deposit(amount, 0);

        vm.prank(address(signer));
        vm.expectRevert(LiminalAdapter.NoAccess.selector);
        adapter.depositAllExcept(amount, 0);

        vm.prank(address(signer));
        vm.expectRevert(LiminalAdapter.NoAccess.selector);
        adapter.redeem(amount);

        vm.prank(address(signer));
        vm.expectRevert(LiminalAdapter.NoAccess.selector);
        adapter.redeemAllExcept(amount);

        vm.prank(address(signer));
        vm.expectRevert(LiminalAdapter.NoAccess.selector);
        adapter.requestRedeem(amount);

        vm.prank(address(signer));
        vm.expectRevert(LiminalAdapter.NoAccess.selector);
        adapter.requestRedeemAllExcept(amount);
    }

    function _fulfill(uint256 requestedShares) private {
        deal(address(USDC), ADMIN, 1 ether);

        address[] memory owners = new address[](1);
        owners[0] = address(adapter);

        uint256[] memory shares = new uint256[](1);
        shares[0] = requestedShares;

        vm.prank(ADMIN);
        RedemptionPipe.fulfillRedeems(owners, shares);
    }

    function _assertManagedAssets(uint256 amount) private {
        vm.prank(address(hyperCrocVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);

        assertEq(assets[0], address(XHYPE));
        assertEq(amounts[0], amount);

        (assets, amounts) = adapter.getManagedAssets(address(hyperCrocVault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);

        assertEq(assets[0], address(XHYPE));
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
}
