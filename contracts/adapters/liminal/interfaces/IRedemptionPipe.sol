// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IRedemptionPipe {
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
}