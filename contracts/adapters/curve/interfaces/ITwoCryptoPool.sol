// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ITwoCryptoPool {
    function add_liquidity(uint256[2] calldata amounts, uint256 minMintAmount, address receiver)
        external
        payable
        returns (uint256);

    function remove_liquidity(uint256 amount, uint256[2] calldata minAmounts, address receiver)
        external
        returns (uint256[2] memory);
}
