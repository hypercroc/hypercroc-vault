// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILiquidityPool {
    function deposit() external payable returns (uint256);

    function withdraw(address _recipient, uint256 _amount) external returns (uint256);

    function requestWithdraw(address recipient, uint256 amount) external returns (uint256);

    function withdrawRequestNFT() external view returns (address);

    function eETH() external view returns (address);

    function getTotalPooledEther() external view returns (uint256);
}
