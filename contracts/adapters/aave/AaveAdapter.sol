// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {AdapterBase} from "../AdapterBase.sol";

contract AaveAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Asserts for address;

    bytes4 public constant getAdapterId = bytes4(keccak256("AaveAdapter"));

    IPoolAddressesProvider public immutable aavePoolAddressProvider;

    constructor(address _aavePoolAddressProvider) {
        _aavePoolAddressProvider.assertNotZeroAddress();
        aavePoolAddressProvider = IPoolAddressesProvider(_aavePoolAddressProvider);
    }

    function supply(address asset, uint256 amount) public {
        IPool aavePool = IPool(aavePoolAddressProvider.getPool());

        IAdapterCallback(msg.sender).adapterCallback(address(this), asset, amount);
        IERC20(asset).forceApprove(address(aavePool), amount);
        aavePool.supply(asset, amount, msg.sender, 0);

        emit Swap(msg.sender, asset, amount, _getAToken(aavePool, asset), amount);
    }

    ///@dev Use call supplyAllExcept(asset, 0) to supply all balance,
    ///      or supplyAllExcept(asset, IERC20(asset).balanceOf(msg.sender)) - to supply prev action result
    function supplyAllExcept(address asset, uint256 except) external {
        uint256 supplyAmount = IERC20(asset).balanceOf(msg.sender) - except;
        supply(asset, supplyAmount);
    }

    function withdraw(address asset, uint256 amount) external returns (uint256 withdrawnAmount) {
        IPool aavePool = IPool(aavePoolAddressProvider.getPool());
        address aToken = _getAToken(aavePool, asset);
        withdrawnAmount = _withdraw(asset, aavePool, aToken, amount);
    }

    function withdrawAllExcept(address asset, uint256 except) external returns (uint256 withdrawnAmount) {
        IPool aavePool = IPool(aavePoolAddressProvider.getPool());
        address aToken = _getAToken(aavePool, asset);
        uint256 amount = IERC20(aToken).balanceOf(msg.sender) - except;
        withdrawnAmount = _withdraw(asset, aavePool, aToken, amount);
    }

    function _getAToken(IPool pool, address asset) private view returns (address) {
        return pool.getReserveData(asset).aTokenAddress;
    }

    function _withdraw(address asset, IPool aavePool, address aToken, uint256 amount)
        private
        returns (uint256 withdrawnAmount)
    {
        uint256 toTransfer = amount == type(uint256).max ? IERC20(aToken).balanceOf(msg.sender) : amount;
        IAdapterCallback(msg.sender).adapterCallback(address(this), aToken, toTransfer);
        IERC20(asset).forceApprove(aToken, toTransfer);

        withdrawnAmount = aavePool.withdraw(asset, amount, msg.sender);

        emit Swap(msg.sender, aToken, toTransfer, asset, withdrawnAmount);
    }
}
