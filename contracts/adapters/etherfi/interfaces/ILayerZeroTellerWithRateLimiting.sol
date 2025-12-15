// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface ILayerZeroTellerWithRateLimiting {
    function deposit(IERC20 depositAsset, uint256 depositAmount, uint256 minimumMint)
        external
        returns (uint256 shares);
}
