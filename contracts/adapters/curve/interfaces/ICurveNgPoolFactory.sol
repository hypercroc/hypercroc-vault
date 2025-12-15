// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICurveNgPoolFactory {
    function get_coins(address pool) external view returns (address[] memory);

    function get_n_coins(address pool) external view returns (uint256);
}
