// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IWithdrawRequestNFT {
    struct WithdrawRequest {
        uint96 amountOfEEth;
        uint96 shareOfEEth;
        bool isValid;
        uint32 feeGwei;
    }

    function claimWithdraw(uint256 requestId) external;

    function isFinalized(uint256 requestId) external view returns (bool);

    function isValid(uint256 requestId) external view returns (bool);

    function getRequest(uint256 requestId) external view returns (WithdrawRequest memory);
}
