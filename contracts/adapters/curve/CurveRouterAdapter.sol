// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AdapterBase} from "../AdapterBase.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {ICurveRouterNg} from "./interfaces/ICurveRouterNg.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";

contract CurveRouterAdapter is AdapterBase {
    using Asserts for address;
    using SafeERC20 for IERC20;

    bytes4 public constant getAdapterId = bytes4(keccak256("CurveRouterAdapter"));

    ICurveRouterNg public immutable s_curveRouter;

    error CurveRouterAdapter__SlippageProtection();

    constructor(address curveRouter) {
        curveRouter.assertNotZeroAddress();
        s_curveRouter = ICurveRouterNg(curveRouter);
    }

    ///@notice Exchange exact amount of token for another token
    ///@dev Receiver of output token is msg.sender.
    ///@dev https://docs.curve.finance/router/CurveRouterNG
    ///@param route Array of [initial token, pool or zap, token, pool or zap, token, ...]
    ///              The array is iterated until a pool address of 0x00, then the last
    ///              given token is transferred to `_receiver`
    ///@param swapParams Multidimensional array of [i, j, swap_type, pool_type, n_coins] where
    ///                         i is the index of input token
    ///                         j is the index of output token
    ///                         For ERC4626:
    ///                             i == 0 - asset -> share
    ///                             i == 1 - share -> asset

    ///                         The swap_type should be:
    ///                         1. for `exchange`,
    ///                         2. for `exchange_underlying`,
    ///                         3. for underlying exchange via zap: factory stable metapools with lending base pool `exchange_underlying`
    ///                            and factory crypto-meta pools underlying exchange (`exchange` method in zap)
    ///                         4. for coin -> LP token "exchange" (actually `add_liquidity`),
    ///                         5. for lending pool underlying coin -> LP token "exchange" (actually `add_liquidity`),
    ///                         6. for LP token -> coin "exchange" (actually `remove_liquidity_one_coin`)
    ///                         7. for LP token -> lending or fake pool underlying coin "exchange" (actually `remove_liquidity_one_coin`)
    ///                         8. for ETH <-> WETH, ETH -> stETH or ETH -> frxETH, stETH <-> wstETH, ETH -> wBETH
    ///                         9. for ERC4626 asset <-> share

    ///                         pool_type: 1 - stable, 2 - twocrypto, 3 - tricrypto, 4 - llamma
    ///                                    10 - stable-ng, 20 - twocrypto-ng, 30 - tricrypto-ng

    ///                         n_coins is the number of coins in pool
    ///@param amount The amount of input token (`_route[0]`) to be sent.
    ///@param minDy The minimum amount received after the final swap.
    ///@param pools Array of pools for swaps via zap contracts. This parameter is only needed for swap_type = 3.
    ///@return amountOut Received amount of the final output token.
    function exchange(
        address[11] calldata route,
        uint256[5][5] calldata swapParams,
        uint256 amount,
        uint256 minDy,
        address[5] calldata pools
    ) public returns (uint256 amountOut) {
        address tokenIn = route[0];
        address tokenOut = route[10]; // assume last token is output token
        if (tokenOut == address(0)) {
            unchecked {
                for (uint256 i = 4; i <= 10; i += 2) {
                    if (route[i] == address(0)) {
                        tokenOut = route[i - 2];
                        break;
                    }
                }
            }
        }

        IAdapterCallback(msg.sender).adapterCallback(address(this), tokenIn, amount);

        ICurveRouterNg curveRouter = s_curveRouter;
        IERC20(tokenIn).forceApprove(address(curveRouter), amount);
        amountOut = curveRouter.exchange(route, swapParams, amount, minDy, pools, msg.sender);

        if (amountOut < minDy) {
            revert CurveRouterAdapter__SlippageProtection();
        }

        emit Swap(msg.sender, tokenIn, amount, tokenOut, amountOut);
    }

    function exchangeAllExcept(
        address[11] calldata route,
        uint256[5][5] calldata swapParams,
        uint256 except,
        uint256 minDy,
        address[5] calldata pools
    ) external returns (uint256 amountOut) {
        uint256 amountIn = IERC20(route[0]).balanceOf(msg.sender) - except;
        return exchange(route, swapParams, amountIn, minDy, pools);
    }
}
