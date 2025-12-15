// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC4626AdapterBase} from "../ERC4626AdapterBase.sol";

contract MakerDaoDaiAdapter is ERC4626AdapterBase {
    bytes4 public constant getAdapterId = bytes4(keccak256("MakerDaoDaiAdapter"));

    constructor(address _sDAI) ERC4626AdapterBase(_sDAI) {}

    function DAI() external view returns (address) {
        return _asset;
    }

    function sDAI() external view returns (address) {
        return _vault;
    }
}
