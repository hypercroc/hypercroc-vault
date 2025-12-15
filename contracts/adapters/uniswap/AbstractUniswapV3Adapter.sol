// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Asserts} from "../../libraries/Asserts.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {AdapterBase} from "../AdapterBase.sol";

abstract contract AbstractUniswapV3Adapter is AdapterBase {
    using Asserts for address;
    using SafeERC20 for IERC20;

    ISwapRouter public immutable uniswapV3Router;

    error WrongRecipient(address vault, address recipient);

    constructor(address _router) {
        _router.assertNotZeroAddress();
        uniswapV3Router = ISwapRouter(_router);
    }

    function swapExactInputV3(ISwapRouter.ExactInputParams memory params) public returns (uint256 amountOut) {
        if (params.recipient != msg.sender) revert WrongRecipient(msg.sender, params.recipient);

        (address inputToken, address outputToken) = decodeTokens(params.path);

        IAdapterCallback(msg.sender).adapterCallback(address(this), inputToken, params.amountIn);
        ISwapRouter _uniswapV3Router = uniswapV3Router;
        IERC20(inputToken).forceApprove(address(_uniswapV3Router), params.amountIn);
        amountOut = _uniswapV3Router.exactInput(params);

        emit Swap(msg.sender, inputToken, params.amountIn, outputToken, amountOut);
    }

    /// @dev Swap all tokenIn, except params.amountIn
    function swapExactInputV3AllExcept(ISwapRouter.ExactInputParams memory params)
        external
        returns (uint256 amountOut)
    {
        (address inputToken,) = decodeTokens(params.path);
        params.amountIn = IERC20(inputToken).balanceOf(msg.sender) - params.amountIn;
        amountOut = swapExactInputV3(params);
    }

    function swapExactOutputV3(ISwapRouter.ExactOutputParams calldata params) external returns (uint256 amountIn) {
        if (params.recipient != msg.sender) revert WrongRecipient(msg.sender, params.recipient);

        (address outputToken, address inputToken) = decodeTokens(params.path);

        IAdapterCallback(msg.sender).adapterCallback(address(this), inputToken, params.amountInMaximum);

        ISwapRouter _uniswapV3Router = uniswapV3Router;
        IERC20(inputToken).forceApprove(address(_uniswapV3Router), params.amountInMaximum);
        amountIn = _uniswapV3Router.exactOutput(params);

        uint256 unused = params.amountInMaximum - amountIn;
        if (unused != 0) {
            IERC20(inputToken).forceApprove(address(_uniswapV3Router), 0);
            IERC20(inputToken).safeTransfer(msg.sender, unused);
        }

        emit Swap(msg.sender, inputToken, amountIn, outputToken, params.amountOut);
    }

    function decodeTokens(bytes memory path) private pure returns (address firstToken, address lastToken) {
        uint256 offset = path.length - 20;
        assembly {
            firstToken := div(mload(add(add(path, 0x20), 0)), 0x1000000000000000000000000)
            lastToken := div(mload(add(add(path, 0x20), offset)), 0x1000000000000000000000000)
        }
    }
}
