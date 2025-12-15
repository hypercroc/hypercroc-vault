// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC4626AdapterBase} from "../ERC4626AdapterBase.sol";

contract MakerDaoUsdsAdapter is ERC4626AdapterBase {
    bytes4 public constant getAdapterId = bytes4(keccak256("MakerDaoUsdsAdapter"));

    constructor(address _sUSDS) ERC4626AdapterBase(_sUSDS) {}

    function USDS() external view returns (address) {
        return _asset;
    }

    function sUSDS() external view returns (address) {
        return _vault;
    }
}
