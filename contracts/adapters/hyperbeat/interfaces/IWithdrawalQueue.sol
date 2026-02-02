// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IWithdrawalQueue {
    struct WithdrawalRequest {
        uint256 nonce;
        address initiator;
        address user;
        uint256 amount;
        uint256 createdAt;
        uint128 exchangeRate;
        uint256 baseAssetAmount;
        uint256 minAssetOut;
        uint64 deadline;
    }

    function instantWithdraw(address _user, uint256 _amount) external;

    function createWithdrawalRequest(
        address _user,
        uint256 _amount,
        uint256 _minAssetOut,
        uint64 _deadline
    )
        external
        returns (WithdrawalRequest memory);
}