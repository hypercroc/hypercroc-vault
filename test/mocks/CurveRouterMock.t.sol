// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CurveRouterMock {
    uint256 private s_offset;

    /* Mock function */
    function setOffset(uint256 offset) external {
        s_offset = offset;
    }

    function exchange(
        address[11] memory route,
        uint256[5][5] memory, /*swapParams*/
        uint256 amount,
        uint256 minDy,
        address[5] memory, /*pools*/
        address receiver
    ) external returns (uint256 actualOut) {
        address tokenIn = route[0];
        address tokenOut = route[10];
        if (tokenOut == address(0)) {
            for (uint256 i = 3; i < 11; ++i) {
                if (route[i] == address(0)) {
                    tokenOut = route[i - 1];
                    break;
                }
            }
        }

        IERC20(tokenIn).transferFrom(msg.sender, address(this), amount);
        actualOut = minDy - s_offset;
        IERC20(tokenOut).transfer(receiver, actualOut);
    }
}
