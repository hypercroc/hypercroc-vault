// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @title Library with general assertion checks
library Asserts {
    /// @notice Revert reason if `assertNotZeroAmount` assert fails
    error ZeroAmount();
    /// @notice Revert reason if `assertNotZeroAddress` assert fails
    error ZeroAddress();
    error SameValue();

    /**
     * @notice Asserts if `input` value is 0
     * @dev Useful for amount (e.g. deposit or withdrawal) assertions
     * @param input uint256 value to check
     */
    function assertNotZeroAmount(uint256 input) internal pure {
        if (input == 0) revert ZeroAmount();
    }

    /**
     * @notice Asserts if `input` value is address(0)
     * @dev Useful for addresses assertions before writing them in a storage
     * @param input address value to check
     */
    function assertNotZeroAddress(address input) internal pure {
        if (input == address(0)) revert ZeroAddress();
    }

    function assertNotSameValue(uint256 left, uint256 right) internal pure {
        if (left == right) revert SameValue();
    }

    function assertNotSameValue(address left, address right) internal pure {
        if (left == right) revert SameValue();
    }
}
