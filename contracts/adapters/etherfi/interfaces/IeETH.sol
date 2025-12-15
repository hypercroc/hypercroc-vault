// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IeETH is IERC20 {
    function totalShares() external view returns (uint256);
}
