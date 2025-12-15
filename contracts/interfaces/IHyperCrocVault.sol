// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IHyperCrocVault is IERC4626 {
    function trackedAssetPosition(address trackedAsset) external view returns (uint256);

    function oracle() external view returns (address);

    function withdrawalQueue() external view returns (address withdrawalQueue);

    function requestRedeem(uint256 shares) external returns (uint256 requestId);

    function requestWithdrawal(uint256 assets) external returns (uint256 requestId);
}
