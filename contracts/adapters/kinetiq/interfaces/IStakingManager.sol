// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IStakingManager {
    struct WithdrawalRequest {
        uint256 hypeAmount; // Amount in HYPE to withdraw
        uint256 kHYPEAmount; // Amount in kHYPE to burn (excluding fee)
        uint256 kHYPEFee; // Fee amount in kHYPE tokens
        uint256 bufferUsed; // Amount fulfilled from hypeBuffer
        uint256 timestamp; // Request timestamp
    }

    function kHYPE() external view returns (address);

    /// @notice Gets the minimum stake amount per transaction
    function minStakeAmount() external view returns (uint256);

    /// @notice Gets the maximum stake amount per transaction
    function maxStakeAmount() external view returns (uint256);

    /// @notice Gets the minimum withdrawal amount per transaction
    function minWithdrawalAmount() external view returns (uint256);

    function nextWithdrawalId(address user) external view returns (uint256);

    /// @notice Gets the withdrawal delay period
    function withdrawalDelay() external view returns (uint256);

    /// @notice Gets withdrawal request details for a user
    function withdrawalRequests(address user, uint256 id) external view returns (WithdrawalRequest memory);

    /// @notice Stakes HYPE tokens
    function stake() external payable;

    /// @notice Queues a withdrawal request
    function queueWithdrawal(uint256 amount) external;

    /// @notice Confirms a withdrawal request
    function confirmWithdrawal(uint256 withdrawalId) external;
}