// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAdapter {
    /// @notice Emitted when one vault token is swapped to the other (stakes and similar actions included)
    event Swap(address indexed vault, address assetIn, uint256 amountIn, address assetOut, uint256 amountOut);

    /// @notice Get the identifier of adapter
    /// @dev HyperCroc adapters should implement this function
    function getAdapterId() external view returns (bytes4);
}
