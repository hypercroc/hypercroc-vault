// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AddressToBytes32Lib} from "./AddressToBytes32Lib.sol";

contract ChainValues {
    using AddressToBytes32Lib for address;
    using AddressToBytes32Lib for bytes32;

    uint256 public constant HYPER_EVM = 999;

    address public constant USD = 0x0000000000000000000000000000000000000348;
    address public constant BTC = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;

    mapping(string chainName => mapping(string valueName => bytes32 value)) private s_values;

    error ChainValues__ZeroAddress(string chainName, string valueName);
    error ChainValues__ZeroBytes32(string chainName, string valueName);
    error ChainValues__ValueAlreadySet(string chainName, string valueName);

    constructor() {

    }

    function getChainName() public view returns (string memory) {
        if (block.chainid == HYPER_EVM) {
            return "hyperEvm";
        }

        revert("Not supported chainId");
    }

    function getAddress(string memory valueName) public view returns (address a) {
        a = getAddress(getChainName(), valueName);
    }

    function getAddress(string memory chainName, string memory valueName) public view returns (address a) {
        a = s_values[chainName][valueName].toAddress();
        if (a == address(0)) {
            revert ChainValues__ZeroAddress(chainName, valueName);
        }
    }

    function getERC20(string memory valueName) public view returns (ERC20 erc20) {
        erc20 = getERC20(getChainName(), valueName);
    }

    function getERC20(string memory chainName, string memory valueName) public view returns (ERC20 erc20) {
        address a = getAddress(chainName, valueName);
        erc20 = ERC20(a);
    }

    function getBytes32(string memory valueName) public view returns (bytes32 b) {
        b = getBytes32(getChainName(), valueName);
    }

    function getBytes32(string memory chainName, string memory valueName) public view returns (bytes32 b) {
        b = s_values[chainName][valueName];
        if (b == bytes32(0)) {
            revert ChainValues__ZeroBytes32(chainName, valueName);
        }
    }

    function setValue(bool overrideOk, string memory valueName, bytes32 value) public {
        setValue(overrideOk, getChainName(), valueName, value);
    }

    function setValue(bool overrideOk, string memory chainName, string memory valueName, bytes32 value) public {
        if (!overrideOk && s_values[chainName][valueName] != bytes32(0)) {
            revert ChainValues__ValueAlreadySet(chainName, valueName);
        }
        s_values[chainName][valueName] = value;
    }

    function setAddress(bool overrideOk, string memory valueName, address value) public {
        setAddress(overrideOk, getChainName(), valueName, value);
    }

    function setAddress(bool overrideOk, string memory chainName, string memory valueName, address value) public {
        setValue(overrideOk, chainName, valueName, value.toBytes32());
    }
}
