// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {MorphoAdapterBase} from "./MorphoAdapterBase.sol";

contract MorphoAdapterV1_1 is MorphoAdapterBase {
    bytes4 public constant getAdapterId = bytes4(keccak256("MorphoAdapterV1_1"));

    constructor(address metaMorphoFactory) MorphoAdapterBase(metaMorphoFactory) {}
}
