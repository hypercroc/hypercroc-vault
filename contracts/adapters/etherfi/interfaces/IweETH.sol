// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IweETH is IERC20 {
    function wrap(uint256 eETHAmount) external returns (uint256 weETHAmount);

    function unwrap(uint256 weETHAmount) external returns (uint256 eETHAmount);

    function getEETHByWeETH(uint256 weETHAmount) external view returns (uint256 eETHAmount);
}
