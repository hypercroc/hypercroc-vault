// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ITriCryptoPool {
    function add_liquidity(uint256[3] calldata amounts, uint256 minMintAmount, bool useETH, address receiver)
        external
        payable
        returns (uint256);

    function remove_liquidity(uint256 amount, uint256[3] calldata minAmounts, bool useEth, address receiver)
        external
        returns (uint256[3] memory);
}
