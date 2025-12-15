// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {TestSetUp} from "./TestSetUp.t.sol";
import {Asserts} from "../contracts/libraries/Asserts.sol";
import {FeeCollector} from "../contracts/base/FeeCollector.sol";

contract FeeCollectorTest is TestSetUp {
    using Math for uint256;

    uint256 constant ONE = 1_000_000;
    uint48 constant FEE = 100_000; // 10%
    uint256 constant DEPOSIT_AMOUNT = 10_000_000;

    function setUp() public override {
        super.setUp();

        asset.mint(USER, 2 * DEPOSIT_AMOUNT);
        vm.prank(USER);
        asset.approve(address(hyperCrocVault), 2 * DEPOSIT_AMOUNT);
        vm.prank(USER);
        hyperCrocVault.deposit(DEPOSIT_AMOUNT, USER);
    }

    function testManagementFee() public {
        hyperCrocVault.setManagementFeeIR(FEE);

        uint256 totalAssetsBefore = hyperCrocVault.totalAssets();
        skip(365 days);

        uint256 toRedeem = hyperCrocVault.maxRedeem(USER);
        vm.prank(USER);
        hyperCrocVault.transfer(address(withdrawalQueue), toRedeem);

        vm.prank(address(withdrawalQueue));
        hyperCrocVault.redeem(toRedeem, address(withdrawalQueue), address(withdrawalQueue));

        uint256 feeCollectorAssets = totalAssetsBefore.mulDiv(FEE, ONE);

        assertEq(hyperCrocVault.getFeeCollectorStorage().lastFeeTimestamp, block.timestamp);
        assertEq(hyperCrocVault.totalAssets(), feeCollectorAssets);
        assertEq(hyperCrocVault.maxWithdraw(FEE_COLLECTOR), feeCollectorAssets);

        vm.prank(USER);
        hyperCrocVault.deposit(DEPOSIT_AMOUNT, USER);
        skip(365 days);

        toRedeem = hyperCrocVault.maxRedeem(USER);
        vm.prank(USER);
        hyperCrocVault.transfer(address(withdrawalQueue), toRedeem);

        vm.prank(address(withdrawalQueue));
        hyperCrocVault.redeem(toRedeem, address(withdrawalQueue), address(withdrawalQueue));

        feeCollectorAssets += DEPOSIT_AMOUNT.mulDiv(FEE, ONE);

        assertEq(hyperCrocVault.getFeeCollectorStorage().lastFeeTimestamp, block.timestamp);
        assertEq(hyperCrocVault.totalAssets(), feeCollectorAssets);
        assertEq(hyperCrocVault.maxWithdraw(FEE_COLLECTOR), feeCollectorAssets);
    }

    function testPerformanceFeeIncrease() public {
        hyperCrocVault.setPerformanceFeeRatio(FEE);

        uint256 totalAssetsBefore = hyperCrocVault.totalAssets();
        asset.mint(address(hyperCrocVault), totalAssetsBefore);

        uint256 toRedeem = hyperCrocVault.maxRedeem(USER);
        uint256 expectedAssets = hyperCrocVault.convertToAssets(toRedeem);
        vm.prank(USER);
        hyperCrocVault.transfer(address(withdrawalQueue), toRedeem);

        vm.prank(address(withdrawalQueue));
        uint256 assets = hyperCrocVault.redeem(toRedeem, address(withdrawalQueue), address(withdrawalQueue));

        assertEq(expectedAssets, assets);
        assertEq(hyperCrocVault.totalAssets(), totalAssetsBefore.mulDiv(FEE, ONE));
        assertApproxEqAbs(hyperCrocVault.getFeeCollectorStorage().highWaterMarkPerShare, 2 * 10 ** hyperCrocVault.decimals(), 1);
    }

    function testPreviewMintWithFee() public {
        hyperCrocVault.setPerformanceFeeRatio(FEE);

        uint256 totalAssetsBefore = hyperCrocVault.totalAssets();
        asset.mint(address(hyperCrocVault), totalAssetsBefore);

        uint256 toMint = 10 ** hyperCrocVault.decimals();
        uint256 expectedAssets = hyperCrocVault.previewMint(toMint);
        assertApproxEqAbs(hyperCrocVault.convertToAssets(toMint), expectedAssets, 1);

        vm.prank(USER);
        uint256 assets = hyperCrocVault.mint(toMint, USER);

        assertEq(expectedAssets, assets);
        assertApproxEqAbs(hyperCrocVault.getFeeCollectorStorage().highWaterMarkPerShare, 2 * 10 ** hyperCrocVault.decimals(), 1);
    }

    function testPreviewDepositWithFee() public {
        hyperCrocVault.setPerformanceFeeRatio(FEE);

        uint256 totalAssetsBefore = hyperCrocVault.totalAssets();
        asset.mint(address(hyperCrocVault), totalAssetsBefore);

        uint256 toDeposit = 10 ** asset.decimals();
        uint256 expectedShares = hyperCrocVault.previewDeposit(toDeposit);
        assertApproxEqAbs(hyperCrocVault.convertToShares(toDeposit), expectedShares, 1);

        vm.prank(USER);
        uint256 shares = hyperCrocVault.deposit(toDeposit, USER);

        assertEq(expectedShares, shares);
        assertApproxEqAbs(hyperCrocVault.getFeeCollectorStorage().highWaterMarkPerShare, 2 * 10 ** hyperCrocVault.decimals(), 1);
    }

    function testPreviewRedeemWithFee() public {
        hyperCrocVault.setPerformanceFeeRatio(FEE);

        uint256 totalAssetsBefore = hyperCrocVault.totalAssets();
        asset.mint(address(hyperCrocVault), totalAssetsBefore);

        uint256 toRedeem = hyperCrocVault.maxRedeem(USER);
        uint256 expectedAssets = hyperCrocVault.previewRedeem(toRedeem);
        assertApproxEqAbs(hyperCrocVault.convertToAssets(toRedeem), expectedAssets, 1);

        vm.prank(USER);
        hyperCrocVault.transfer(address(withdrawalQueue), toRedeem);

        vm.prank(address(withdrawalQueue));
        uint256 assets = hyperCrocVault.redeem(toRedeem, address(withdrawalQueue), address(withdrawalQueue));

        assertEq(expectedAssets, assets);
        assertEq(hyperCrocVault.totalAssets(), totalAssetsBefore.mulDiv(FEE, ONE));
        assertApproxEqAbs(hyperCrocVault.getFeeCollectorStorage().highWaterMarkPerShare, 2 * 10 ** hyperCrocVault.decimals(), 1);
    }

    function testPreviewWithdrawWithFee() public {
        hyperCrocVault.setPerformanceFeeRatio(FEE);

        uint256 totalAssetsBefore = hyperCrocVault.totalAssets();
        asset.mint(address(hyperCrocVault), totalAssetsBefore);

        uint256 toWithdraw = hyperCrocVault.maxWithdraw(USER);
        uint256 expectedShares = hyperCrocVault.previewWithdraw(toWithdraw);
        assertApproxEqAbs(hyperCrocVault.convertToShares(toWithdraw), expectedShares, 1);

        vm.prank(USER);
        hyperCrocVault.transfer(address(withdrawalQueue), expectedShares);

        vm.prank(address(withdrawalQueue));
        uint256 shares = hyperCrocVault.withdraw(toWithdraw, address(withdrawalQueue), address(withdrawalQueue));

        assertEq(expectedShares, shares);
        assertEq(hyperCrocVault.totalAssets(), totalAssetsBefore.mulDiv(FEE, ONE));
        assertApproxEqAbs(hyperCrocVault.getFeeCollectorStorage().highWaterMarkPerShare, 2 * 10 ** hyperCrocVault.decimals(), 1);
    }

    function testPerformanceFeeDecrease() public {
        hyperCrocVault.setPerformanceFeeRatio(FEE);

        uint256 totalAssetsBefore = hyperCrocVault.totalAssets();
        asset.burn(address(hyperCrocVault), totalAssetsBefore / 2);

        uint256 toRedeem = hyperCrocVault.maxRedeem(USER);
        vm.prank(USER);
        hyperCrocVault.transfer(address(withdrawalQueue), toRedeem);

        vm.prank(address(withdrawalQueue));
        hyperCrocVault.redeem(toRedeem, address(withdrawalQueue), address(withdrawalQueue));

        assertEq(hyperCrocVault.totalAssets(), 0);
    }

    function testSetFeeCollector() public {
        address newFeeCollector = address(0xFEE2);
        vm.expectEmit(address(hyperCrocVault));
        emit FeeCollector.FeeCollectorSet(newFeeCollector);

        hyperCrocVault.setFeeCollector(newFeeCollector);
        assertEq(hyperCrocVault.getFeeCollectorStorage().feeCollector, newFeeCollector);
    }

    function testSetFeeCollectorOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
        hyperCrocVault.setFeeCollector(NO_ACCESS);
    }

    function testSetFeeCollectorSameValue() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.SameValue.selector));
        hyperCrocVault.setFeeCollector(FEE_COLLECTOR);
    }

    function testSetFeeCollectorZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAddress.selector));
        hyperCrocVault.setFeeCollector(address(0));
    }

    function testSetManagementFeeIR() public {
        vm.expectEmit(address(hyperCrocVault));
        emit FeeCollector.ManagementFeeIRSet(FEE);

        hyperCrocVault.setManagementFeeIR(FEE);
        assertEq(hyperCrocVault.getFeeCollectorStorage().managementFeeIR, FEE);
    }

    function testSetManagementFeeIROnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
        hyperCrocVault.setManagementFeeIR(FEE);
    }

    function testSetManagementFeeIRSameValue() public {
        hyperCrocVault.setManagementFeeIR(FEE);
        vm.expectRevert(abi.encodeWithSelector(Asserts.SameValue.selector));
        hyperCrocVault.setManagementFeeIR(FEE);
    }

    function testSetPerformanceFeeRatio() public {
        vm.expectEmit(address(hyperCrocVault));
        emit FeeCollector.PerformanceFeeRatioSet(FEE);

        hyperCrocVault.setPerformanceFeeRatio(FEE);
        assertEq(hyperCrocVault.getFeeCollectorStorage().performanceFeeRatio, FEE);
    }

    function testSetPerformanceFeeRatioOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
        hyperCrocVault.setPerformanceFeeRatio(FEE);
    }

    function testSetPerformanceFeeRatioSameValue() public {
        hyperCrocVault.setPerformanceFeeRatio(FEE);
        vm.expectRevert(abi.encodeWithSelector(Asserts.SameValue.selector));
        hyperCrocVault.setPerformanceFeeRatio(FEE);
    }
}
