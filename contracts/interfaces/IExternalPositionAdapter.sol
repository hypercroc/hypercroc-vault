// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title interface for adapters that open external positions (e.g. Aave, Compound, HyperCroc pools)
interface IExternalPositionAdapter {
    /// @notice Returns managed assets by the vault in adapter Protocol
    function getManagedAssets() external view returns (address[] memory assets, uint256[] memory amounts);

    /// @notice Returns debt assets managed by the vault in adapter Protocol
    function getDebtAssets() external view returns (address[] memory assets, uint256[] memory amounts);
}
