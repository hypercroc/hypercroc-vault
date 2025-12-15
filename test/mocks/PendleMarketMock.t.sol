// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {MintableERC20} from "./MintableERC20.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStandardizedYield} from "@pendle/core-v2/interfaces/IStandardizedYield.sol";
import {IPPrincipalToken} from "@pendle/core-v2/interfaces/IPPrincipalToken.sol";
import {IPYieldToken} from "@pendle/core-v2/interfaces/IPYieldToken.sol";

/// @dev Mintable ERC20 token.
contract PendleMarketMock is MintableERC20 {
    address private immutable ptToken;
    address private immutable syToken;
    bool private s_isExpired;
    address private s_rewardToken;
    uint256 private s_rewards; // 10 tokens with 18 decimals

    constructor(address _ptToken, address _syToken, string memory name, string memory symbol, uint8 decimals_)
        MintableERC20(name, symbol, decimals_)
    {
        ptToken = _ptToken;
        syToken = _syToken;
    }

    function readTokens() external view returns (IStandardizedYield _SY, IPPrincipalToken _PT, IPYieldToken _YT) {
        return (IStandardizedYield(syToken), IPPrincipalToken(ptToken), IPYieldToken(address(0)));
    }

    function setExpired(bool _isExpired) external {
        s_isExpired = _isExpired;
    }

    function isExpired() external view returns (bool) {
        return s_isExpired;
    }

    function setRewards(uint256 _rewards) external {
        s_rewards = _rewards;
    }

    function setRewardToken(address _rewardToken) external {
        s_rewardToken = _rewardToken;
    }

    function getRewardTokens() external view returns (address[] memory rewardTokens) {
        rewardTokens = new address[](1);
        rewardTokens[0] = s_rewardToken; // Assuming the mock token itself is a reward token
    }

    function redeemRewards(address user) external returns (uint256[] memory rewards) {
        rewards = new uint256[](1);
        rewards[0] = s_rewards;
        IERC20(s_rewardToken).transfer(user, s_rewards);
    }
}
