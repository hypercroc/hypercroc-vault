// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAtomicQueue {
    struct AtomicRequest {
        uint64 deadline;
        uint88 atomicPrice;
        uint96 offerAmount;
        bool inSolve;
    }

    function updateAtomicRequest(IERC20 offer, IERC20 want, AtomicRequest calldata userRequest) external;

    function getUserAtomicRequest(address user, IERC20 offer, IERC20 want)
        external
        view
        returns (AtomicRequest memory);
}
