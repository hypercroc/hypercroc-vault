// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {TestSetUp} from "./TestSetUp.t.sol";
import {AdapterActionExecutor} from "../contracts/base/AdapterActionExecutor.sol";
import {VaultAccessControl} from "../contracts/base/VaultAccessControl.sol";
import {AdapterMock} from "./mocks/AdapterMock.t.sol";
import {ExternalPositionAdapterMock} from "./mocks/ExternalPositionAdapterMock.t.sol";

contract AdapterActionExecutorTest is TestSetUp {
    using Math for uint256;

    uint24 private constant ONE_PERCENT_SLIPPAGE = 10_000;
    uint24 private constant ONE_SLIPPAGE = 1_000_000;

    function testAddAdapter() public {
        vm.expectEmit(address(hyperCrocVault));
        emit AdapterActionExecutor.NewAdapterAdded(adapter.getAdapterId(), address(adapter));

        hyperCrocVault.addAdapter(address(adapter));
        assertEq(address(hyperCrocVault.getAdapter(adapter.getAdapterId())), address(adapter));
        assertEq(hyperCrocVault.externalPositionAdapterPosition(address(adapter)), 0);
    }

    function testAddExternalPositionAdapter() public {
        vm.expectEmit(address(hyperCrocVault));
        emit AdapterActionExecutor.NewAdapterAdded(
            externalPositionAdapter.getAdapterId(), address(externalPositionAdapter)
        );

        vm.expectEmit(address(hyperCrocVault));
        emit AdapterActionExecutor.NewExternalPositionAdapterAdded(address(externalPositionAdapter), 1);

        hyperCrocVault.addAdapter(address(externalPositionAdapter));

        assertEq(
            address(hyperCrocVault.getAdapter(externalPositionAdapter.getAdapterId())), address(externalPositionAdapter)
        );
        assertEq(hyperCrocVault.externalPositionAdapterPosition(address(externalPositionAdapter)), 1);
    }

    function testAddAdapterOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
        hyperCrocVault.addAdapter(address(adapter));
    }

    function testAddAdapterAlreadyExists() public {
        hyperCrocVault.addAdapter(address(adapter));

        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.AdapterAlreadyExists.selector, address(adapter)));
        hyperCrocVault.addAdapter(address(adapter));
    }

    function testAddAdapterWrongAddress() public {
        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.WrongAddress.selector));
        hyperCrocVault.addAdapter(address(asset));
    }

    function testAddExternalPositionAdapterExceedsLimit() public {
        hyperCrocVault.setMaxExternalPositionAdapters(0);
        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.ExceedsAdapterLimit.selector));
        hyperCrocVault.addAdapter(address(externalPositionAdapter));
    }

    function testRemoveAdapter() public {
        hyperCrocVault.addAdapter(address(adapter));

        vm.expectEmit(address(hyperCrocVault));
        emit AdapterActionExecutor.AdapterRemoved(adapter.getAdapterId());

        hyperCrocVault.removeAdapter(address(adapter));
        assertEq(address(hyperCrocVault.getAdapter(adapter.getAdapterId())), address(0));
    }

    function testRemoveExternalPositionAdapterLast() public {
        hyperCrocVault.addAdapter(address(externalPositionAdapter));

        vm.expectEmit(address(hyperCrocVault));
        emit AdapterActionExecutor.AdapterRemoved(externalPositionAdapter.getAdapterId());

        vm.expectEmit(address(hyperCrocVault));
        emit AdapterActionExecutor.ExternalPositionAdapterRemoved(address(externalPositionAdapter), 1, address(0));

        hyperCrocVault.removeAdapter(address(externalPositionAdapter));

        assertEq(address(hyperCrocVault.getAdapter(adapter.getAdapterId())), address(0));
        assertEq(hyperCrocVault.externalPositionAdapterPosition(address(externalPositionAdapter)), 0);
    }

    function testRemoveExternalPositionAdapterNotLast() public {
        ExternalPositionAdapterMock secondExternalPositionAdapter =
            new ExternalPositionAdapterMock(address(externalPositionManagedAsset), address(externalPositionDebtAsset));
        secondExternalPositionAdapter.setAdapterId(bytes4(keccak256("SecondExternalPositionAdapterMock")));

        hyperCrocVault.addAdapter(address(externalPositionAdapter));
        hyperCrocVault.addAdapter(address(secondExternalPositionAdapter));

        assertEq(hyperCrocVault.externalPositionAdapterPosition(address(externalPositionAdapter)), 1);
        assertEq(hyperCrocVault.externalPositionAdapterPosition(address(secondExternalPositionAdapter)), 2);

        vm.expectEmit(address(hyperCrocVault));
        emit AdapterActionExecutor.AdapterRemoved(externalPositionAdapter.getAdapterId());

        vm.expectEmit(address(hyperCrocVault));
        emit AdapterActionExecutor.ExternalPositionAdapterRemoved(
            address(externalPositionAdapter), 1, address(secondExternalPositionAdapter)
        );

        hyperCrocVault.removeAdapter(address(externalPositionAdapter));

        assertEq(address(hyperCrocVault.getAdapter(adapter.getAdapterId())), address(0));
        assertEq(hyperCrocVault.externalPositionAdapterPosition(address(externalPositionAdapter)), 0);
        assertEq(hyperCrocVault.externalPositionAdapterPosition(address(secondExternalPositionAdapter)), 1);
    }

    function testRemoveAdapterOnlyOwner() public {
        hyperCrocVault.addAdapter(address(adapter));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
        hyperCrocVault.removeAdapter(address(adapter));
    }

    function testRemoveAdapterUnknownAdapter() public {
        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.UnknownAdapter.selector, adapter.getAdapterId()));
        hyperCrocVault.removeAdapter(address(adapter));
    }

    function testExecuteAdapterAction() public {
        hyperCrocVault.addAdapter(address(adapter));
        hyperCrocVault.addAdapter(address(externalPositionAdapter));

        AdapterActionExecutor.AdapterActionArg[] memory args = new AdapterActionExecutor.AdapterActionArg[](2);

        bytes memory adapterCalldata = "adapterData";
        bytes memory adapterCalldataWithSelector = abi.encodeWithSelector(adapter.action.selector, adapterCalldata);
        args[0] = AdapterActionExecutor.AdapterActionArg({
            actionSlippage: 0,
            adapterId: adapter.getAdapterId(),
            data: adapterCalldataWithSelector
        });

        bytes memory externalPositionAdapterCalldata = "externalPositionAdapterData";
        bytes memory externalPositionAdapterCalldataWithSelector =
            abi.encodeWithSelector(externalPositionAdapter.action.selector, externalPositionAdapterCalldata);
        args[1] = AdapterActionExecutor.AdapterActionArg({
            actionSlippage: 0,
            adapterId: externalPositionAdapter.getAdapterId(),
            data: externalPositionAdapterCalldataWithSelector
        });

        vm.expectEmit(address(hyperCrocVault));
        emit AdapterActionExecutor.AdapterActionExecuted(
            adapter.getAdapterId(), adapterCalldataWithSelector, abi.encode(uint256(1))
        );

        vm.expectEmit(address(hyperCrocVault));
        emit AdapterActionExecutor.AdapterActionExecuted(
            externalPositionAdapter.getAdapterId(), externalPositionAdapterCalldataWithSelector, abi.encode(uint256(1))
        );

        vm.prank(VAULT_MANAGER);
        hyperCrocVault.executeAdapterAction(args);

        assertEq(adapter.actionsExecuted(), 1);
        assertEq(adapter.recentCalldata(), adapterCalldata);

        assertEq(externalPositionAdapter.actionsExecuted(), 1);
        assertEq(externalPositionAdapter.recentCalldata(), externalPositionAdapterCalldata);
    }

    function testExecuteAdapterActionOnlyRole() public {
        hyperCrocVault.addAdapter(address(adapter));
        hyperCrocVault.addAdapter(address(externalPositionAdapter));

        AdapterActionExecutor.AdapterActionArg[] memory args = new AdapterActionExecutor.AdapterActionArg[](2);

        bytes memory adapterCalldata = "adapterData";
        bytes memory adapterCalldataWithSelector = abi.encodeWithSelector(adapter.action.selector, adapterCalldata);
        args[0] = AdapterActionExecutor.AdapterActionArg({
            actionSlippage: 0,
            adapterId: adapter.getAdapterId(),
            data: adapterCalldataWithSelector
        });

        bytes memory externalPositionAdapterCalldata = "externalPositionAdapterData";
        bytes memory externalPositionAdapterCalldataWithSelector =
            abi.encodeWithSelector(externalPositionAdapter.action.selector, externalPositionAdapterCalldata);
        args[1] = AdapterActionExecutor.AdapterActionArg({
            actionSlippage: 0,
            adapterId: externalPositionAdapter.getAdapterId(),
            data: externalPositionAdapterCalldataWithSelector
        });

        vm.expectRevert(abi.encodeWithSelector(VaultAccessControl.NoAccess.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
        hyperCrocVault.executeAdapterAction(args);
    }

    function testExecuteAdapterActionUnknownAdapter() public {
        AdapterActionExecutor.AdapterActionArg[] memory args = new AdapterActionExecutor.AdapterActionArg[](1);

        bytes memory adapterCalldata = "adapterData";
        bytes memory adapterCalldataWithSelector = abi.encodeWithSelector(adapter.action.selector, adapterCalldata);
        args[0] = AdapterActionExecutor.AdapterActionArg({
            actionSlippage: 0,
            adapterId: adapter.getAdapterId(),
            data: adapterCalldataWithSelector
        });

        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.UnknownAdapter.selector, adapter.getAdapterId()));
        vm.prank(VAULT_MANAGER);
        hyperCrocVault.executeAdapterAction(args);
    }

    function testAdapterCallback() public {
        hyperCrocVault.addAdapter(address(externalPositionAdapter));

        uint256 amount = 10 ** 18;
        uint256 managedAssetAmount = amount * 3 / 2;
        uint256 debtAssetAmount = amount / 2;
        asset.mint(address(hyperCrocVault), amount);

        AdapterActionExecutor.AdapterActionArg[] memory args = new AdapterActionExecutor.AdapterActionArg[](1);
        bytes memory adapterCalldataWithSelector = abi.encodeWithSelector(
            externalPositionAdapter.deposit.selector, address(asset), amount, managedAssetAmount, debtAssetAmount
        );
        args[0] = AdapterActionExecutor.AdapterActionArg({
            actionSlippage: 0,
            adapterId: externalPositionAdapter.getAdapterId(),
            data: adapterCalldataWithSelector
        });

        vm.prank(VAULT_MANAGER);
        hyperCrocVault.executeAdapterAction(args);

        assertEq(asset.balanceOf(address(hyperCrocVault)), 0);
        assertEq(externalPositionManagedAsset.balanceOf(address(hyperCrocVault)), managedAssetAmount);
        assertEq(externalPositionDebtAsset.balanceOf(address(hyperCrocVault)), debtAssetAmount);
    }

    function testAdapterCallbackForbidden() public {
        hyperCrocVault.addAdapter(address(externalPositionAdapter));

        ExternalPositionAdapterMock fakeAdapter =
            new ExternalPositionAdapterMock(address(externalPositionManagedAsset), address(externalPositionDebtAsset));

        assertNotEq(address(hyperCrocVault.getAdapter(fakeAdapter.getAdapterId())), address(0));
        assertNotEq(address(hyperCrocVault.getAdapter(fakeAdapter.getAdapterId())), address(fakeAdapter));

        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.Forbidden.selector));
        fakeAdapter.callback(address(hyperCrocVault), address(asset), 1);
    }

    function testTotalAssets() public {
        hyperCrocVault.addAdapter(address(externalPositionAdapter));

        uint256 expectedTotalAssets;
        assertEq(hyperCrocVault.totalAssets(), expectedTotalAssets);

        uint256 externalPositionManagedAssetAmount = 10 ** 15;
        externalPositionManagedAsset.mint(address(hyperCrocVault), externalPositionManagedAssetAmount);
        expectedTotalAssets +=
            oracle.getQuote(externalPositionManagedAssetAmount, address(externalPositionManagedAsset), address(asset));
        assertEq(hyperCrocVault.totalAssets(), expectedTotalAssets);

        uint256 externalPositionDebtAssetAmount = 10 ** 9;
        externalPositionDebtAsset.mint(address(hyperCrocVault), externalPositionDebtAssetAmount);
        expectedTotalAssets -=
            oracle.getQuote(externalPositionDebtAssetAmount, address(externalPositionDebtAsset), address(asset));
        assertEq(hyperCrocVault.totalAssets(), expectedTotalAssets);
    }

    function testSetMaxExternalPositionAdapters() public {
        uint8 maxExternalPositionAdapters = 10;
        hyperCrocVault.setMaxExternalPositionAdapters(maxExternalPositionAdapters);

        assertEq(hyperCrocVault.maxExternalPositionAdapters(), maxExternalPositionAdapters);
    }

    function testSetMaxExternalPositionAdaptersWrongValue() public {
        hyperCrocVault.addAdapter(address(externalPositionAdapter));
        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.WrongValue.selector));
        hyperCrocVault.setMaxExternalPositionAdapters(0);
    }

    function testSetMaxExternalPositionAdaptersOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
        hyperCrocVault.setMaxExternalPositionAdapters(0);
    }

    function testSetMaxSlippage() public {
        uint24 maxSlippage = ONE_SLIPPAGE / 3;
        hyperCrocVault.setMaxSlippage(maxSlippage);

        assertEq(hyperCrocVault.maxSlippage(), maxSlippage);
    }

    function testSetMaxSlippageWrongValue() public {
        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.WrongValue.selector));
        hyperCrocVault.setMaxSlippage(ONE_SLIPPAGE);
    }

    function testSetMaxSlippageOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
        hyperCrocVault.setMaxSlippage(ONE_SLIPPAGE);
    }

    function testExecuteAdapterLowSlippage() public {
        asset.mint(address(hyperCrocVault), ONE_SLIPPAGE);

        hyperCrocVault.setMaxSlippage(ONE_PERCENT_SLIPPAGE);
        hyperCrocVault.addAdapter(address(adapter));

        AdapterActionExecutor.AdapterActionArg[] memory args = new AdapterActionExecutor.AdapterActionArg[](1);

        uint256 totalAssets = hyperCrocVault.totalAssets();
        uint256 slipped = totalAssets.mulDiv(ONE_PERCENT_SLIPPAGE, ONE_SLIPPAGE);
        bytes memory adapterCalldataWithSelector = abi.encodeWithSelector(adapter.slippage.selector, asset, slipped);
        args[0] = AdapterActionExecutor.AdapterActionArg({
            actionSlippage: ONE_PERCENT_SLIPPAGE,
            adapterId: adapter.getAdapterId(),
            data: adapterCalldataWithSelector
        });

        vm.prank(VAULT_MANAGER);
        hyperCrocVault.executeAdapterAction(args);
    }

    function testExecuteAdapterTooMuchTotalSlippage() public {
        asset.mint(address(hyperCrocVault), ONE_SLIPPAGE);

        hyperCrocVault.setMaxSlippage(ONE_PERCENT_SLIPPAGE);
        hyperCrocVault.addAdapter(address(adapter));

        AdapterActionExecutor.AdapterActionArg[] memory args = new AdapterActionExecutor.AdapterActionArg[](1);

        uint256 totalAssets = hyperCrocVault.totalAssets();
        uint256 slipped = totalAssets.mulDiv(ONE_PERCENT_SLIPPAGE, ONE_SLIPPAGE) + 1;
        bytes memory adapterCalldataWithSelector = abi.encodeWithSelector(adapter.slippage.selector, asset, slipped);
        args[0] = AdapterActionExecutor.AdapterActionArg({
            actionSlippage: ONE_PERCENT_SLIPPAGE,
            adapterId: adapter.getAdapterId(),
            data: adapterCalldataWithSelector
        });

        vm.prank(VAULT_MANAGER);
        vm.expectRevert(
            abi.encodeWithSelector(AdapterActionExecutor.TooMuchSlippage.selector, totalAssets, totalAssets - slipped)
        );
        hyperCrocVault.executeAdapterAction(args);
    }

    function testExecuteAdapterWrongSlippageValue() public {
        asset.mint(address(hyperCrocVault), ONE_SLIPPAGE);

        hyperCrocVault.setMaxSlippage(ONE_PERCENT_SLIPPAGE);
        hyperCrocVault.addAdapter(address(adapter));

        AdapterActionExecutor.AdapterActionArg[] memory args = new AdapterActionExecutor.AdapterActionArg[](1);

        uint256 totalAssets = hyperCrocVault.totalAssets();
        uint256 slipped = totalAssets.mulDiv(ONE_PERCENT_SLIPPAGE, ONE_SLIPPAGE);
        bytes memory adapterCalldataWithSelector = abi.encodeWithSelector(adapter.slippage.selector, asset, slipped);
        uint24 wrongSlippage = ONE_PERCENT_SLIPPAGE + 1;
        args[0] = AdapterActionExecutor.AdapterActionArg({
            actionSlippage: wrongSlippage,
            adapterId: adapter.getAdapterId(),
            data: adapterCalldataWithSelector
        });

        vm.prank(VAULT_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.WrongSlippageValue.selector, 0));
        hyperCrocVault.executeAdapterAction(args);
    }
}
