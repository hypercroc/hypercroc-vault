// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAdapterCallback} from "../interfaces/IAdapterCallback.sol";
import {Asserts} from "../libraries/Asserts.sol";
import {AdapterBase} from "./AdapterBase.sol";

abstract contract ERC4626AdapterBase is AdapterBase {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC4626;
    using Asserts for address;

    address internal immutable _vault;
    address internal immutable _asset;

    constructor(address vault) {
        vault.assertNotZeroAddress();

        _vault = vault;
        _asset = IERC4626(_vault).asset();
    }

    function deposit(uint256 assets) external virtual returns (uint256 shares) {
        shares = _deposit(_vault, _asset, assets);
    }

    function depositAllExcept(uint256 except) external virtual returns (uint256 shares) {
        address asset = _asset;
        uint256 assets = IERC20(asset).balanceOf(msg.sender) - except;
        shares = _deposit(_vault, asset, assets);
    }

    function redeem(uint256 shares) external virtual returns (uint256 withdrawn) {
        withdrawn = _redeem(_vault, shares);
    }

    function redeemAllExcept(uint256 exceptShares) external virtual returns (uint256 withdrawn) {
        address vault = _vault;
        uint256 shares = IERC4626(vault).balanceOf(msg.sender) - exceptShares;
        withdrawn = _redeem(vault, shares);
    }

    function _deposit(address vault, address asset, uint256 assets) private returns (uint256 shares) {
        IAdapterCallback(msg.sender).adapterCallback(address(this), asset, assets);
        IERC20(asset).forceApprove(vault, assets);

        shares = IERC4626(vault).deposit(assets, msg.sender);

        emit Swap(msg.sender, asset, assets, vault, shares);
    }

    function _redeem(address vault, uint256 shares) private returns (uint256 withdrawn) {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(vault), shares);
        withdrawn = IERC4626(vault).redeem(shares, msg.sender, address(this));

        emit Swap(msg.sender, vault, shares, _asset, withdrawn);
    }
}
