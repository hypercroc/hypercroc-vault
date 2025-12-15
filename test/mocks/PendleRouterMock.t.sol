// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPMarket} from "@pendle/core-v2/interfaces/IPMarket.sol";
import {IPPrincipalToken} from "@pendle/core-v2/interfaces/IPPrincipalToken.sol";
import {
    TokenInput,
    ApproxParams,
    LimitOrderData,
    SwapData,
    TokenOutput
} from "@pendle/core-v2/interfaces/IPAllActionTypeV3.sol";
import {IPSwapAggregator, SwapDataExtra} from "@pendle/core-v2/router/swap-aggregator/IPSwapAggregator.sol";

/// @dev Mintable ERC20 token.
contract PendleRouterMock {
    mapping(address market => address ptToken) private s_ptTokens;
    uint256 private s_offset;
    uint256 private s_rollOverOffset;
    address private s_redeemPt;

    /* Mock function */
    function addOffset(uint256 offset) external {
        s_offset = offset;
    }

    function addRollOverOffset(uint256 offset) external {
        s_rollOverOffset = offset;
    }

    function swapExactTokenForPt(
        address receiver,
        address market,
        uint256 minPtOut,
        ApproxParams calldata, /*guessPtOut*/
        TokenInput calldata input,
        LimitOrderData calldata /*limit*/
    ) external payable returns (uint256 netPtOut, uint256 netSyFee, uint256 netSyInterm) {
        uint256 ptOut = minPtOut - s_offset;
        (, IPPrincipalToken ptToken,) = IPMarket(market).readTokens();
        IERC20(input.tokenIn).transferFrom(msg.sender, address(this), input.netTokenIn);
        IERC20(ptToken).transfer(receiver, ptOut);
        return (ptOut, 0, 0);
    }

    function swapExactPtForToken(
        address receiver,
        address market,
        uint256 exactPtIn,
        TokenOutput calldata output,
        LimitOrderData calldata /*limit*/
    ) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm) {
        uint256 tokenOut = output.minTokenOut + s_rollOverOffset - s_offset;
        (, IPPrincipalToken ptToken,) = IPMarket(market).readTokens();
        IERC20(ptToken).transferFrom(msg.sender, address(this), exactPtIn);
        IERC20(output.tokenOut).transfer(receiver, tokenOut);
        return (tokenOut, 0, 0);
    }

    function addLiquiditySingleToken(
        address receiver,
        address market,
        uint256 minLpOut,
        ApproxParams calldata, /*guessPtReceivedFromSy*/
        TokenInput calldata input,
        LimitOrderData calldata /*limit*/
    ) external payable returns (uint256 netLpOut, uint256 netSyFee, uint256 netSyInterm) {
        uint256 lpOut = minLpOut - s_offset;
        IERC20(input.tokenIn).transferFrom(msg.sender, address(this), input.netTokenIn);
        IERC20(market).transfer(receiver, lpOut);
        return (lpOut, 0, 0);
    }

    function removeLiquiditySingleToken(
        address receiver,
        address market,
        uint256 netLpToRemove,
        TokenOutput calldata output,
        LimitOrderData calldata /*limit*/
    ) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm) {
        uint256 tokenOut = output.minTokenOut - s_offset;
        IERC20(market).transferFrom(msg.sender, address(this), netLpToRemove);
        IERC20(output.tokenOut).transfer(receiver, tokenOut);
        return (tokenOut, 0, 0);
    }

    /* Mock function */
    function setRedeemPt(address pt) external {
        s_redeemPt = pt;
    }

    function redeemPyToToken(address receiver, address, /*ytToken*/ uint256 ptIn, TokenOutput calldata output)
        external
        returns (uint256 netTokenOut, uint256 netSyInterm)
    {
        uint256 tokenOut = output.minTokenOut - s_offset;
        IERC20(s_redeemPt).transferFrom(msg.sender, address(this), ptIn);
        IERC20(output.tokenOut).transfer(receiver, tokenOut);
        return (tokenOut, 0);
    }

    function swapTokensToTokens(
        IPSwapAggregator, /*pendleSwap*/
        SwapDataExtra[] calldata swaps,
        uint256[] calldata netSwaps
    ) external payable returns (uint256[] memory netOutFromSwaps) {
        uint256 netOut = swaps[0].minOut - s_offset;
        netOutFromSwaps = new uint256[](1);
        netOutFromSwaps[0] = netOut;

        IERC20(swaps[0].tokenIn).transferFrom(msg.sender, address(this), netSwaps[0]);
        IERC20(swaps[0].tokenOut).transfer(msg.sender, netOut);
    }
}
