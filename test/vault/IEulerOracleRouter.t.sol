// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {IEulerPriceOracle} from "contracts/interfaces/IEulerPriceOracle.sol";

/// @title EulerRouter
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Default Oracle resolver for Euler lending products.
/// @dev Integration Note: The router supports pricing via `convertToAssets` for trusted `resolvedVaults`.
/// By ERC4626 spec `convert*` ignores liquidity restrictions, fees, slippage and per-user restrictions.
/// Therefore the reported price may not be realizable through `redeem` or `withdraw`.
interface IEulerOracleRouter is IEulerPriceOracle {
    function govSetConfig(address base, address quote, address oracle) external;

    /// @notice Configure an ERC4626 vault to use internal pricing via `convert*` methods.
    /// @param vault The address of the ERC4626 vault.
    /// @param set True to configure the vault, false to clear the record.
    /// @dev Callable only by the governor. Vault must implement ERC4626.
    /// Note: Before configuring a vault verify that its `convertToAssets` is secure.
    function govSetResolvedVault(address vault, bool set) external;

    function getQuote(uint256 inAmount, address base, address quote) external view returns (uint256);

    function getQuotes(uint256 inAmount, address base, address quote) external view returns (uint256, uint256);

    /// @notice Get the PriceOracle configured for base/quote.
    /// @param base The address of the base token.
    /// @param quote The address of the quote token.
    /// @return The configured `PriceOracle` for the pair or `address(0)` if no oracle is configured.
    function getConfiguredOracle(address base, address quote) external view returns (address);
    /// @notice Resolve the PriceOracle to call for a given base/quote pair.
    /// @param inAmount The amount of `base` to convert.
    /// @param base The token that is being priced.
    /// @param quote The token that is the unit of account.
    /// @dev Implements the following resolution logic:
    /// 1. Check the base case: `base == quote` and terminate if true.
    /// 2. If a PriceOracle is configured for base/quote in the `oracles` mapping, return it.
    /// 3. If `base` is configured as a resolved ERC4626 vault, call `convertToAssets(inAmount)`
    /// and continue the recursion, substituting the ERC4626 `asset` for `base`.
    /// 4. As a last resort, return the fallback oracle or revert if it is not set.
    /// @return The resolved amount. This value may be different from the original `inAmount`
    /// if the resolution path included an ERC4626 vault present in `resolvedVaults`.
    /// @return The resolved base.
    /// @return The resolved quote.
    /// @return The resolved PriceOracle to call.
    function resolveOracle(uint256 inAmount, address base, address quote)
        external
        view
        returns (uint256, /* resolvedAmount */ address, /* base */ address, /* quote */ address); /* oracle */
}
