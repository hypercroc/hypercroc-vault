// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniversalRewardsDistributorBase} from
    "../../contracts/adapters/morpho/interfaces/IUniversalRewardsDistributorBase.sol";

contract MorphoRewardsDistributorMock is IUniversalRewardsDistributorBase {
    function claim(address account, address reward, uint256 claimable, bytes32[] memory /*proof*/ )
        external
        returns (uint256 amount)
    {
        IERC20(reward).transfer(account, claimable);
        return claimable;
    }
}
