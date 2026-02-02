// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IDepositor {
    function deposit(address _token, address _receiver, uint256 _amount, bytes32 _builderCode) external;
}