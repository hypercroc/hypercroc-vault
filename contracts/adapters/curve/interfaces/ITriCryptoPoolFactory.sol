// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ITriCryptoPoolFactory {
    function get_coins(address pool) external view returns (address[3] memory);
}
