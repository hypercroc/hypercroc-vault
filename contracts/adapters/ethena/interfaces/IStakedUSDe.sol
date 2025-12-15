// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IStakedUSDe is IERC4626 {
    struct UserCooldown {
        uint104 cooldownEnd;
        uint152 underlyingAmount;
    }

    function unstake(address receiver) external;

    function cooldownAssets(uint256 assets) external returns (uint256 shares);

    function cooldownShares(uint256 shares) external returns (uint256 assets);

    function cooldownDuration() external view returns (uint24);

    function cooldowns(address user) external view returns (UserCooldown memory);
}
