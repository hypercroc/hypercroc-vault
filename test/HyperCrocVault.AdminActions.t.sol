// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {TestSetUp} from "./TestSetUp.t.sol";
import {Asserts} from "../contracts/libraries/Asserts.sol";
import {MultiAssetVaultBase} from "../contracts/base/MultiAssetVaultBase.sol";
import {AdapterActionExecutor} from "../contracts/base/AdapterActionExecutor.sol";
import {VaultAccessControl} from "../contracts/base/VaultAccessControl.sol";
import {OraclePriceProvider} from "../contracts/base/OraclePriceProvider.sol";
import {MintableERC20} from "./mocks/MintableERC20.t.sol";
import {EulerRouterMock} from "./mocks/EulerRouterMock.t.sol";

contract HyperCrocVaultAdminActionsTest is TestSetUp {
    function testAddNewAsset() public {
        assertEq(hyperCrocVault.trackedAssetPosition(address(trackedAsset)), 0);

        vm.expectEmit(address(hyperCrocVault));
        emit MultiAssetVaultBase.NewTrackedAssetAdded(address(trackedAsset), 1);
        hyperCrocVault.addTrackedAsset(address(trackedAsset));

        assertEq(hyperCrocVault.trackedAssetPosition(address(trackedAsset)), 1);
        assertEq(hyperCrocVault.trackedAssetsCount(), 1);
    }

    function testAddNewAssetOnlyOwner() public {
        vm.prank(NO_ACCESS);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        hyperCrocVault.addTrackedAsset(address(trackedAsset));
    }

    function testAddNewAssetAlreadyTracked() public {
        hyperCrocVault.addTrackedAsset(address(trackedAsset));

        vm.expectRevert(
            abi.encodeWithSelector(
                MultiAssetVaultBase.AlreadyTracked.selector, hyperCrocVault.trackedAssetPosition(address(trackedAsset))
            )
        );
        hyperCrocVault.addTrackedAsset(address(trackedAsset));
    }

    function testAddNewAssetExceedsLimit() public {
        hyperCrocVault.setMaxTrackedAssets(0);

        vm.expectRevert(abi.encodeWithSelector(MultiAssetVaultBase.ExceedsTrackedAssetsLimit.selector));
        hyperCrocVault.addTrackedAsset(address(trackedAsset));
    }

    function testAddNewAssetZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAddress.selector));
        hyperCrocVault.addTrackedAsset(address(0));
    }

    function testAddNewAssetOracleNotExist() public {
        MintableERC20 secondTrackedAsset = new MintableERC20("wstUSDTest", "wstUSDTest", 6);
        vm.expectRevert(
            abi.encodeWithSelector(
                OraclePriceProvider.OracleNotExist.selector, address(secondTrackedAsset), hyperCrocVault.asset()
            )
        );
        hyperCrocVault.addTrackedAsset(address(secondTrackedAsset));
    }

    function testRemoveLastAsset() public {
        hyperCrocVault.addTrackedAsset(address(trackedAsset));

        vm.expectEmit(address(hyperCrocVault));
        emit MultiAssetVaultBase.TrackedAssetRemoved(address(trackedAsset), 1, address(0));
        hyperCrocVault.removeTrackedAsset(address(trackedAsset));

        assertEq(hyperCrocVault.trackedAssetPosition(address(trackedAsset)), 0);
        assertEq(hyperCrocVault.trackedAssetsCount(), 0);
    }

    function testRemoveNotLastAsset() public {
        hyperCrocVault.addTrackedAsset(address(trackedAsset));
        MintableERC20 secondTrackedAsset = new MintableERC20("wstUSDTest", "wstUSDTest", 6);
        oracle.setPrice(oracle.ONE(), address(secondTrackedAsset), address(asset));
        hyperCrocVault.addTrackedAsset(address(secondTrackedAsset));

        assertEq(hyperCrocVault.trackedAssetPosition(address(trackedAsset)), 1);
        assertEq(hyperCrocVault.trackedAssetPosition(address(secondTrackedAsset)), 2);

        vm.expectEmit(address(hyperCrocVault));
        emit MultiAssetVaultBase.TrackedAssetRemoved(address(trackedAsset), 1, address(secondTrackedAsset));
        hyperCrocVault.removeTrackedAsset(address(trackedAsset));

        assertEq(hyperCrocVault.trackedAssetPosition(address(trackedAsset)), 0);
        assertEq(hyperCrocVault.trackedAssetPosition(address(secondTrackedAsset)), 1);
        assertEq(hyperCrocVault.trackedAssetsCount(), 1);
    }

    function testRemoveAssetOnlyOwner() public {
        hyperCrocVault.addTrackedAsset(address(trackedAsset));

        vm.prank(NO_ACCESS);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        hyperCrocVault.removeTrackedAsset(address(trackedAsset));
    }

    function testRemoveNotTrackedAsset() public {
        vm.expectRevert(abi.encodeWithSelector(MultiAssetVaultBase.NotTrackedAsset.selector));
        hyperCrocVault.removeTrackedAsset(address(trackedAsset));
    }

    function testRemoveAssetNotZeroBalance() public {
        hyperCrocVault.addTrackedAsset(address(trackedAsset));

        uint256 balance = 1;
        trackedAsset.mint(address(hyperCrocVault), balance);

        vm.expectRevert(abi.encodeWithSelector(MultiAssetVaultBase.NotZeroBalance.selector, balance));
        hyperCrocVault.removeTrackedAsset(address(trackedAsset));
    }

    function testSetMinDeposit() public {
        uint256 newMinDeposit = hyperCrocVault.minimalDeposit() + 1;

        vm.expectEmit(address(hyperCrocVault));
        emit MultiAssetVaultBase.MinimalDepositSet(newMinDeposit);
        hyperCrocVault.setMinimalDeposit(newMinDeposit);

        assertEq(hyperCrocVault.minimalDeposit(), newMinDeposit);
    }

    function testSetMinDepositOnlyOwner() public {
        uint256 newMinDeposit = hyperCrocVault.minimalDeposit() + 1;

        vm.prank(NO_ACCESS);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        hyperCrocVault.setMinimalDeposit(newMinDeposit);
    }

    function testSetMinDepositSameValue() public {
        uint256 newMinDeposit = hyperCrocVault.minimalDeposit();

        vm.expectRevert(abi.encodeWithSelector(Asserts.SameValue.selector));
        hyperCrocVault.setMinimalDeposit(newMinDeposit);
    }

    function testSetMaxTrackedAssets() public {
        uint8 newMaxTrackedAssets = 0;
        vm.expectEmit(address(hyperCrocVault));
        emit MultiAssetVaultBase.MaxTrackedAssetsSet(newMaxTrackedAssets);
        hyperCrocVault.setMaxTrackedAssets(newMaxTrackedAssets);

        assertEq(hyperCrocVault.maxTrackedAssets(), newMaxTrackedAssets);
    }

    function testSetMaxTrackedAssetsOnlyOwner() public {
        vm.prank(NO_ACCESS);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        hyperCrocVault.setMaxTrackedAssets(0);
    }

    function testSetMaxTrackedAssetsWrongValue() public {
        hyperCrocVault.addTrackedAsset(address(trackedAsset));

        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.WrongValue.selector));
        hyperCrocVault.setMaxTrackedAssets(0);
    }

    function testSetOracle() public {
        address newOracle = address(new EulerRouterMock());

        vm.expectEmit(address(hyperCrocVault));
        emit OraclePriceProvider.OracleSet(newOracle);
        hyperCrocVault.setOracle(newOracle);

        assertEq(address(hyperCrocVault.oracle()), newOracle);
    }

    function testSetOracleOnlyOwner() public {
        address newOracle = address(new EulerRouterMock());

        vm.prank(NO_ACCESS);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        hyperCrocVault.setOracle(newOracle);
    }

    function testSetOracleSameValue() public {
        address sameOracle = address(hyperCrocVault.oracle());
        vm.expectRevert(abi.encodeWithSelector(Asserts.SameValue.selector));
        hyperCrocVault.setOracle(sameOracle);
    }

    function testSetOracleZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAddress.selector));
        hyperCrocVault.setOracle(address(0));
    }

    function testAddVaultManagerZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAddress.selector));
        hyperCrocVault.addVaultManager(address(0), true);
    }

    function test_renounceOwnership() public {
        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.Forbidden.selector));
        hyperCrocVaultFactory.renounceOwnership();
    }
}
