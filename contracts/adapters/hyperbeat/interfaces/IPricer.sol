// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IPricer {
    function getAssetAmount(address _token, uint256 _vaultTokenAmount) external view returns (uint256);
}