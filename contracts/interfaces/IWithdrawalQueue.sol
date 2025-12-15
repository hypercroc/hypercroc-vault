// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";

interface IWithdrawalQueue is IERC721 {
    function lastRequestId() external view returns (uint256 requestId);
    function lastFinalizedRequestId() external view returns (uint256);
    function getRequestedShares(uint256 requestId) external view returns (uint256);
    function claimWithdrawal(uint256 requestId, address receiver) external returns (uint256 claimedAssets);
    function finalizeRequests(uint256 requestId) external;
    function addFinalizer(address finalizer, bool add) external;
}
