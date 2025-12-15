// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IEulerPriceOracle} from "../../contracts/interfaces/IEulerPriceOracle.sol";

contract EulerRouterMock is IEulerPriceOracle, Test {
    using Math for uint256;

    string public constant name = "EulerRouterMock";
    uint256 public constant ONE = 2 ** 96;
    mapping(address base => mapping(address quote => uint256)) prices;

    function getQuote(uint256 inAmount, address base, address quote)
        external
        view
        override
        returns (uint256 outAmount)
    {
        return inAmount.mulDiv(prices[base][quote], ONE);
    }

    function getQuotes(uint256, address, address) external pure override returns (uint256, uint256) {
        revert("Not implemented");
    }

    function setPrice(uint256 price, address base, address quote) external {
        prices[base][quote] = price;
        prices[quote][base] = ONE.mulDiv(ONE, price);
    }

    function removePrice(address base, address quote) external {
        delete prices[base][quote];
        delete prices[quote][base];
    }
}
