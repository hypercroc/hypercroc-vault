// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import {TestSetUp} from "./TestSetUp.t.sol";
import {AdapterActionExecutor} from "../contracts/base/AdapterActionExecutor.sol";
import {VaultAccessControl} from "../contracts/base/VaultAccessControl.sol";
import {WithdrawalQueue} from "../contracts/WithdrawalQueue.sol";
import {WithdrawalQueueBase} from "../contracts/base/WithdrawalQueueBase.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {Asserts} from "contracts/libraries/Asserts.sol";

contract HyperCrocWithdrawalQueueTest is TestSetUp {
    uint256 constant DEPOSIT = 1_000_000;

    function setUp() public override {
        super.setUp();
        asset.mint(USER, 10 * DEPOSIT);

        vm.prank(USER);
        asset.approve(address(hyperCrocVault), DEPOSIT);

        vm.prank(USER);
        hyperCrocVault.deposit(DEPOSIT, USER);
        assertEq(hyperCrocVault.balanceOf(USER), DEPOSIT);
    }

    function testRequestWithdrawal() public {
        uint256 assetBalanceBefore = asset.balanceOf(USER);
        uint256 lpBalanceBefore = hyperCrocVault.balanceOf(USER);

        uint256 withdrawalAmount = DEPOSIT / 2;
        uint256 lpBalanceDelta = hyperCrocVault.previewWithdraw(withdrawalAmount);

        vm.prank(USER);
        uint256 requestId = hyperCrocVault.requestWithdrawal(withdrawalAmount);
        assertEq(requestId, 1);
        assertEq(withdrawalQueue.lastRequestId(), 1);

        assertEq(asset.balanceOf(USER), assetBalanceBefore);
        assertEq(lpBalanceBefore - hyperCrocVault.balanceOf(USER), lpBalanceDelta);
        assertEq(hyperCrocVault.balanceOf(address(withdrawalQueue)), lpBalanceDelta);
        assertEq(withdrawalQueue.ownerOf(requestId), USER);

        uint256 requestedShares = withdrawalQueue.getRequestedShares(requestId);
        assertEq(requestedShares, lpBalanceDelta);
    }

    function testRequestWithdrawalZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(Asserts.ZeroAmount.selector);
        hyperCrocVault.requestWithdrawal(0);
    }

    function testRequestWithdrawalExceedsMax() public {
        uint256 lpBalance = hyperCrocVault.balanceOf(USER);
        uint256 maxWithdraw = hyperCrocVault.convertToAssets(lpBalance);
        uint256 exceedsMaxWithdraw = maxWithdraw + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626Upgradeable.ERC4626ExceededMaxWithdraw.selector, USER, exceedsMaxWithdraw, maxWithdraw
            )
        );
        vm.prank(USER);
        hyperCrocVault.requestWithdrawal(exceedsMaxWithdraw);
    }

    function testDirectPoolWithdrawFail() public {
        vm.expectRevert(abi.encodeWithSelector(VaultAccessControl.NoAccess.selector, USER));
        vm.prank(USER);
        hyperCrocVault.withdraw(DEPOSIT, USER, USER);
    }

    function testRequestRedeem() public {
        uint256 assetBalanceBefore = asset.balanceOf(USER);
        uint256 lpBalanceBefore = hyperCrocVault.balanceOf(USER);

        uint256 lpBalanceDelta = lpBalanceBefore / 2;

        vm.prank(USER);
        uint256 requestId = hyperCrocVault.requestRedeem(lpBalanceDelta);
        assertEq(requestId, 1);

        assertEq(asset.balanceOf(USER), assetBalanceBefore);
        assertEq(lpBalanceBefore - hyperCrocVault.balanceOf(USER), lpBalanceDelta);
        assertEq(hyperCrocVault.balanceOf(address(withdrawalQueue)), lpBalanceDelta);
        assertEq(withdrawalQueue.ownerOf(requestId), USER);

        uint256 requestedShares = withdrawalQueue.getRequestedShares(requestId);
        assertEq(requestedShares, lpBalanceDelta);
    }

    function testRequestRedeemZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(Asserts.ZeroAmount.selector);
        hyperCrocVault.requestRedeem(0);
    }

    function testRequestRedeemExceedsMax() public {
        uint256 maxRedeem = hyperCrocVault.balanceOf(USER);
        uint256 exceedsMaxRedeem = maxRedeem + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626Upgradeable.ERC4626ExceededMaxRedeem.selector, USER, exceedsMaxRedeem, maxRedeem
            )
        );
        vm.prank(USER);
        hyperCrocVault.requestRedeem(exceedsMaxRedeem);
    }

    function testDirectPoolRedeemFail() public {
        vm.expectRevert(abi.encodeWithSelector(VaultAccessControl.NoAccess.selector, USER));
        vm.prank(USER);
        hyperCrocVault.redeem(DEPOSIT, USER, USER);
    }

    function testRequestOnlyVault() public {
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueBase.NoAccess.selector, USER));
        vm.prank(USER);
        withdrawalQueue.requestWithdrawal(DEPOSIT, USER);
    }

    function testClaimWithdrawal() public {
        vm.prank(USER);
        uint256 requestId = hyperCrocVault.requestWithdrawal(DEPOSIT);

        vm.prank(FINALIZER);
        withdrawalQueue.finalizeRequests(requestId);
        assertEq(withdrawalQueue.lastFinalizedRequestId(), 1);

        uint256 userBalanceBefore = asset.balanceOf(USER);
        vm.prank(USER);
        withdrawalQueue.claimWithdrawal(requestId, USER);

        assertEq(asset.balanceOf(USER) - userBalanceBefore, DEPOSIT);
        assertEq(hyperCrocVault.balanceOf(address(withdrawalQueue)), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, requestId));
        withdrawalQueue.ownerOf(requestId);

        uint256 requestedShares = withdrawalQueue.getRequestedShares(requestId);
        assertEq(requestedShares, 0);
    }

    function testClaimWithdrawalNotFinalized() public {
        vm.prank(USER);
        uint256 requestId = hyperCrocVault.requestWithdrawal(DEPOSIT);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.NotFinalized.selector));
        vm.prank(USER);
        withdrawalQueue.claimWithdrawal(requestId, USER);
    }

    function testClaimWithdrawalNotRequestOwner() public {
        vm.prank(USER);
        uint256 requestId = hyperCrocVault.requestWithdrawal(DEPOSIT);

        vm.prank(FINALIZER);
        withdrawalQueue.finalizeRequests(requestId);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.NotRequestOwner.selector));
        vm.prank(NO_ACCESS);
        withdrawalQueue.claimWithdrawal(requestId, USER);
    }

    function testFinalizeOnlyFinalizer() public {
        vm.prank(USER);
        uint256 requestId = hyperCrocVault.requestWithdrawal(DEPOSIT);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueBase.NoAccess.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
        withdrawalQueue.finalizeRequests(requestId);
    }

    function testFinalizeAlreadyFinalized() public {
        vm.prank(USER);
        uint256 requestId = hyperCrocVault.requestWithdrawal(DEPOSIT);

        vm.prank(FINALIZER);
        withdrawalQueue.finalizeRequests(requestId);

        vm.prank(FINALIZER);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueBase.AlreadyFinalized.selector));
        withdrawalQueue.finalizeRequests(requestId);
    }

    function testFinalizeFutureFinalization() public {
        vm.prank(USER);
        uint256 requestId = hyperCrocVault.requestWithdrawal(DEPOSIT);

        vm.prank(FINALIZER);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueBase.FutureFinalization.selector));
        withdrawalQueue.finalizeRequests(requestId + 1);
    }

    function testAddFinalizerNoAccess() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
        withdrawalQueue.addFinalizer(NO_ACCESS, true);
    }

    function testAddFinalizerZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAddress.selector));
        withdrawalQueue.addFinalizer(address(0), true);
    }

    function test_renounceOwnership() public {
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.Forbidden.selector));
        hyperCrocVaultFactory.renounceOwnership();
    }
}
