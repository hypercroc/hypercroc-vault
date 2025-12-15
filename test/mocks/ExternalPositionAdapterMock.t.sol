// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAdapter} from "../../contracts/interfaces/IAdapter.sol";
import {IExternalPositionAdapter} from "../../contracts/interfaces/IExternalPositionAdapter.sol";
import {IAdapterCallback} from "../../contracts/interfaces/IAdapterCallback.sol";
import {MintableERC20} from "./MintableERC20.t.sol";

contract ExternalPositionAdapterMock is IERC165, IAdapter, IExternalPositionAdapter, Test {
    address private immutable _managedAsset;
    address private immutable _debtAsset;
    bytes4 private _adapterId = bytes4(keccak256("ExternalPositionAdapterMock"));

    uint256 public actionsExecuted = 0;
    bytes public recentCalldata;

    constructor(address managedAsset, address debtAsset) {
        _managedAsset = managedAsset;
        _debtAsset = debtAsset;
    }

    function action(bytes calldata data) external returns (uint256) {
        actionsExecuted += 1;
        recentCalldata = data;
        return actionsExecuted;
    }

    function deposit(address asset, uint256 amount, uint256 managedAssetToMint, uint256 debtAssetToMint) external {
        actionsExecuted += 1;

        IAdapterCallback(msg.sender).adapterCallback(address(this), asset, amount);
        MintableERC20(_managedAsset).mint(msg.sender, managedAssetToMint);
        MintableERC20(_debtAsset).mint(msg.sender, debtAssetToMint);
    }

    function withdraw(address asset, uint256 amount, uint256 managedAssetToBurn, uint256 debtAssetToBurn) external {
        actionsExecuted += 1;

        IERC20(asset).transfer(msg.sender, amount);
        MintableERC20(_managedAsset).burn(msg.sender, managedAssetToBurn);
        MintableERC20(_debtAsset).burn(msg.sender, debtAssetToBurn);
    }

    function callback(address vault, address asset, uint256 amount) external {
        IAdapterCallback(vault).adapterCallback(address(this), asset, amount);
    }

    function setAdapterId(bytes4 newId) external {
        _adapterId = newId;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAdapter).interfaceId || interfaceId == type(IExternalPositionAdapter).interfaceId;
    }

    function getAdapterId() external view override returns (bytes4) {
        return _adapterId;
    }

    function getManagedAssets() external view override returns (address[] memory assets, uint256[] memory amounts) {
        assets = new address[](1);
        assets[0] = _managedAsset;

        amounts = new uint256[](1);
        amounts[0] = IERC20(_managedAsset).balanceOf(msg.sender);
    }

    function getDebtAssets() external view override returns (address[] memory assets, uint256[] memory amounts) {
        assets = new address[](1);
        assets[0] = _debtAsset;

        amounts = new uint256[](1);
        amounts[0] = IERC20(_debtAsset).balanceOf(msg.sender);
    }
}
