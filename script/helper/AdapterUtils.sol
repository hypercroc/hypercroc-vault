// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

enum Adapter {
    AaveAdapter,
    CurveRouterAdapter,
    EthenaAdapter,
    EtherfiETH,
    EtherfiBTC,
    HyperCrocPoolAdapter,
    HyperCrocVaultAdapter,
    Lido,
    MakerDaoDAI,
    MakerDaoUSDS,
    Morpho,
    MorphoV1_1,
    PendleAdapter,
    ResolvAdapter,
    UniswapAdapter
}

abstract contract AdapterUtils {
    function _isPerVaultAdapter(Adapter adapter) internal pure returns (bool) {
        return adapter == Adapter.EthenaAdapter || adapter == Adapter.HyperCrocPoolAdapter || adapter == Adapter.EtherfiBTC;
    }

    function _getAdapterName(Adapter adapter) internal pure returns (string memory) {
        if (adapter == Adapter.AaveAdapter) {
            return "AaveAdapter";
        } else if (adapter == Adapter.CurveRouterAdapter) {
            return "CurveRouterAdapter";
        } else if (adapter == Adapter.EthenaAdapter) {
            return "EthenaAdapter";
        } else if (adapter == Adapter.EtherfiETH) {
            return "EtherfiETHAdapter";
        } else if (adapter == Adapter.EtherfiBTC) {
            return "EtherfiBTCAdapter";
        } else if (adapter == Adapter.HyperCrocPoolAdapter) {
            return "HyperCrocPoolAdapter";
        } else if (adapter == Adapter.HyperCrocVaultAdapter) {
            return "HyperCrocVaultAdapter";
        } else if (adapter == Adapter.Lido) {
            return "LidoAdapter";
        } else if (adapter == Adapter.MakerDaoDAI) {
            return "MakerDaoDaiAdapter";
        } else if (adapter == Adapter.MakerDaoUSDS) {
            return "MakerDaoUsdsAdapter";
        } else if (adapter == Adapter.Morpho) {
            return "MorphoAdapter";
        } else if (adapter == Adapter.MorphoV1_1) {
            return "MorphoAdapterV1_1";
        } else if (adapter == Adapter.PendleAdapter) {
            return "PendleAdapter";
        } else if (adapter == Adapter.ResolvAdapter) {
            return "ResolvAdapter";
        } else if (adapter == Adapter.UniswapAdapter) {
            return "UniswapAdapter";
        }

        revert("Adapter not supported");
    }

    function _getAdapterId(Adapter adapter) internal pure returns (bytes4) {
        string memory adapterName = _getAdapterName(adapter);
        return bytes4(keccak256(bytes(adapterName)));
    }
}
