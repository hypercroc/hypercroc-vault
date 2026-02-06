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
    error ChainValues__ZeroUint8(string chainName, string valueName);
    error ChainValues__ValueAlreadySet(string chainName, string valueName);

    constructor() {
        _addHyperEvmValues();
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

    function getUint8(string memory valueName) public view returns (uint8 b) {
        b = getUint8(getChainName(), valueName);
    }

    function getUint8(string memory chainName, string memory valueName) public view returns (uint8 b) {
        b = uint8(uint256(s_values[chainName][valueName]));
        if (b == 0) {
            revert ChainValues__ZeroUint8(chainName, valueName);
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

    function _addHyperEvmValues() private {
        s_values["hyperEvm"]["EulerOracle"] = 0xA52B0805F30eAB4CA61Ed5f4F051B5a0f863cA4f.toBytes32();

        /* =========== TOKENS ==================== */
        s_values["hyperEvm"]["wHYPE"] = 0x5555555555555555555555555555555555555555.toBytes32();
        s_values["hyperEvm"]["USDT"] = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb.toBytes32();
        s_values["hyperEvm"]["USDC"] = 0xb88339CB7199b77E23DB6E890353E22632Ba630f.toBytes32();
        s_values["hyperEvm"]["hbUSDT"] = 0x5e105266db42f78FA814322Bce7f388B4C2e61eb.toBytes32();
        s_values["hyperEvm"]["hUSDT"] = 0x10982ad645D5A112606534d8567418Cf64c14cB5.toBytes32();
        s_values["hyperEvm"]["xHYPE"] = 0xAc962FA04BF91B7fd0DC0c5C32414E0Ce3C51E03.toBytes32();
        s_values["hyperEvm"]["kHYPE"] = 0xfD739d4e423301CE9385c1fb8850539D657C296D.toBytes32();
        s_values["hyperEvm"]["UETH"] = 0xBe6727B535545C67d5cAa73dEa54865B92CF7907.toBytes32();
        s_values["hyperEvm"]["UBTC"] = 0x9FDBdA0A5e284c32744D2f17Ee5c74B284993463.toBytes32();

        /* ============= CHAINLINK DATA FEEDS =======================*/
        s_values["hyperEvm"]["ChainlinkFeed_USDT_USD"] = 0x9114446540B4f8E0E310041981f7c1Be6181Ed07.toBytes32();
        s_values["hyperEvm"]["ChainlinkFeed_USDC_USD"] = 0xA0Adc43ce7AfE3EE7d7eac3C994E178D0620223B.toBytes32();
        s_values["hyperEvm"]["ChainlinkFeed_HYPE_USD"] = 0xa5a72eF19F82A579431186402425593a559ed352.toBytes32();
        s_values["hyperEvm"]["ChainlinkFeed_UETH_USD"] = 0x54EdE484Bb0E589F5eE13e04c84f46eb787c9C6a.toBytes32();
        s_values["hyperEvm"]["ChainlinkFeed_UBTC_USD"] = 0xd7752D8831a209F5177de52b3b32b5098A7B56b8.toBytes32();
        s_values["hyperEvm"]["ChainlinkFeed_kHYPE_HYPE"] = 0x272deDc9fe4227027b027B016957CF6661120eCB.toBytes32();

        /* ============= PYTH DATA FEEDS =======================*/
        s_values["hyperEvm"]["PythOracle"] = 0xe9d69CdD6Fe41e7B621B4A688C5D1a68cB5c8ADc.toBytes32();
        s_values["hyperEvm"]["PythFeedId_xHYPE_USDC"] = 0x4e3352e8f55536e85d7d9fcb4aa3393326ede1961f36c0bceb75fbb2f36d9b1f;

        /* ============= REDSTONE DATA FEEDS =======================*/
        s_values["hyperEvm"]["RedstoneFeed_hbUSDT_USDT"] = 0x96572d32d699cE463Fdf36610273CC76B7d83f9b.toBytes32();

        /* ============= DEPLOYED EULER ORACLES ========== */
        s_values["hyperEvm"]["Chainlink_USDT_USD_oracle"] = 0x75423551E165213ec9EBE1e3d9F836601181b8a2.toBytes32();
        s_values["hyperEvm"]["Chainlink_USDC_USD_oracle"] = 0x5d4a156089bF6937ECf58eA58a9550Aaa7Bfb3eD.toBytes32();
        s_values["hyperEvm"]["Cross_wHYPE_USDT_oracle"] = 0xB9aB7B26FD9Fa58bF5CFA089dad3D5aB368F288a.toBytes32();
    }
}
