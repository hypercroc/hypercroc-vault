// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {TestSetUp} from "./TestSetUp.t.sol";
import {Asserts} from "../contracts/libraries/Asserts.sol";
import {MultiAssetVaultBase} from "../contracts/base/MultiAssetVaultBase.sol";

contract HyperCrocVaultUserActionsTest is TestSetUp {
    uint256 constant MIN_DEPOSIT = 1_000_000;

    function setUp() public override {
        super.setUp();
        hyperCrocVault.setMinimalDeposit(MIN_DEPOSIT);
        asset.mint(USER, 10 * MIN_DEPOSIT);
    }

    function testTotalAssets() public {
        hyperCrocVault.addTrackedAsset(address(trackedAsset));

        uint256 depositAmount = 10 ** 12;
        asset.mint(address(this), depositAmount);
        asset.approve(address(hyperCrocVault), depositAmount);
        hyperCrocVault.deposit(depositAmount, address(this));

        assertEq(hyperCrocVault.totalAssets(), depositAmount);

        uint256 trackedAssetAmount = 1_000 * 10 ** 18;
        trackedAsset.mint(address(hyperCrocVault), trackedAssetAmount);

        uint256 expectedTotalAssets =
            depositAmount + oracle.getQuote(trackedAssetAmount, address(trackedAsset), address(asset));
        assertEq(hyperCrocVault.totalAssets(), expectedTotalAssets);
    }

    function testDeposit() public {
        vm.prank(USER);
        asset.approve(address(hyperCrocVault), MIN_DEPOSIT);

        vm.prank(USER);
        hyperCrocVault.deposit(MIN_DEPOSIT, USER);
    }

    function testLessThanMinDeposit() public {
        vm.prank(USER);
        asset.approve(address(hyperCrocVault), MIN_DEPOSIT - 1);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(MultiAssetVaultBase.LessThanMinDeposit.selector, MIN_DEPOSIT));
        hyperCrocVault.deposit(MIN_DEPOSIT - 1, USER);
    }

    function testZeroAmount() public {
        hyperCrocVault.setMinimalDeposit(0);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAmount.selector));
        hyperCrocVault.deposit(0, USER);
    }

    function testMint() public {
        vm.prank(USER);
        asset.approve(address(hyperCrocVault), MIN_DEPOSIT);

        vm.prank(USER);
        hyperCrocVault.mint(MIN_DEPOSIT, USER);
    }

    function testLessThanMinDepositMint() public {
        vm.prank(USER);
        asset.approve(address(hyperCrocVault), MIN_DEPOSIT - 1);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(MultiAssetVaultBase.LessThanMinDeposit.selector, MIN_DEPOSIT));
        hyperCrocVault.mint(MIN_DEPOSIT - 1, USER);
    }

    function testZeroAmountMint() public {
        hyperCrocVault.setMinimalDeposit(0);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAmount.selector));
        hyperCrocVault.mint(0, USER);
    }
}
