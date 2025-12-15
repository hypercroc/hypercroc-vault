// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MintableERC20} from "./MintableERC20.t.sol";

contract PendleSyTokenMock is MintableERC20 {
    address private immutable tokenOut;

    constructor(address _tokenOut, string memory name, string memory symbol, uint8 decimals_)
        MintableERC20(name, symbol, decimals_)
    {
        tokenOut = _tokenOut;
    }

    function getTokensOut() external view returns (address[] memory tokensOut) {
        tokensOut = new address[](1);
        tokensOut[0] = tokenOut;
    }
}
