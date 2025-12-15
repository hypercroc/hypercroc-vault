// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    TokenInput,
    ApproxParams,
    LimitOrderData,
    SwapData,
    TokenOutput
} from "@pendle/core-v2/interfaces/IPAllActionTypeV3.sol";
import {IAdapterCallback} from "../../contracts/interfaces/IAdapterCallback.sol";
import {PendleAdapter} from "../../contracts/adapters/pendle/PendleAdapter.sol";

/// @dev Mintable ERC20 token.
contract PendleMarketFactoryMock {
    mapping(address => bool) private s_markets;

    function addMarket(address market, bool add) external {
        s_markets[market] = add;
    }

    function isValidMarket(address market) external view returns (bool) {
        return s_markets[market];
    }
}
