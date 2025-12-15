// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

/// @title IMetaMorphoFactory interface
/// @dev https://github.com/morpho-org/metamorpho/blob/main/src/interfaces/IMetaMorphoFactory.sol
interface IMetaMorphoFactory {
    /// @notice Whether a MetaMorpho vault was created with the factory.
    function isMetaMorpho(address target) external view returns (bool);
}
