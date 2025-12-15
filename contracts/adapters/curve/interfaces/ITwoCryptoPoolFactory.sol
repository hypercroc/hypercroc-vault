// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ITwoCryptoPoolFactory {
    function get_coins(address pool) external view returns (address[2] memory);
}
