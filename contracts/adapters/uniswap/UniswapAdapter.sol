// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {AbstractUniswapV3Adapter} from "./AbstractUniswapV3Adapter.sol";
import {AbstractUniswapV4Adapter} from "./AbstractUniswapV4Adapter.sol";

contract UniswapAdapter is AbstractUniswapV3Adapter, AbstractUniswapV4Adapter {
    bytes4 public constant getAdapterId = bytes4(keccak256("UniswapAdapter"));

    constructor(address v3Router, address universalRouter, address _permit2)
        AbstractUniswapV3Adapter(v3Router)
        AbstractUniswapV4Adapter(universalRouter, _permit2)
    {}
}
