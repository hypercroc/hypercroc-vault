// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICurveRouterNg {
    function exchange(
        address[11] memory route,
        uint256[5][5] memory swapParams,
        uint256 amount,
        uint256 minDy,
        address[5] memory pools,
        address receiver
    ) external returns (uint256);
}
