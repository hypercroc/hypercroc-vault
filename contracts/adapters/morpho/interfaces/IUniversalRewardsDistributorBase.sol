// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

interface IUniversalRewardsDistributorBase {
    function claim(address account, address reward, uint256 claimable, bytes32[] memory proof)
        external
        returns (uint256 amount);
}
