// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC4626AdapterBase} from "../ERC4626AdapterBase.sol";

contract ResolvAdapter is ERC4626AdapterBase {
    bytes4 public constant getAdapterId = bytes4(keccak256("ResolvAdapter"));

    constructor(address _wstUSR) ERC4626AdapterBase(_wstUSR) {}

    function USR() external view returns (address) {
        return _asset;
    }

    function wstUSR() external view returns (address) {
        return _vault;
    }
}
