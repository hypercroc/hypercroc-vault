// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IDepositPipe {
    function asset() external view returns (address);

    function deposit(uint256 assets, address receiver, uint256 minShares) external returns (uint256);
}