// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStETH} from "./IStETH.sol";

/// @title StETH token wrapper with static balances
interface IWstETH is IERC20 {
    function stETH() external view returns (IStETH);

    /// @notice Get amount of wstETH for a given amount of stETH
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);

    /// @notice Get amount of stETH for a given amount of wstETH
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);

    /// @dev Exchanges stETH to wstETH
    function wrap(uint256 _stETHAmount) external returns (uint256);

    /// @dev Exchanges wstETH to stETH
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
}
