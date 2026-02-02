// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AdapterBase} from "../AdapterBase.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {IDepositor} from "./interfaces/IDepositor.sol";
import {IWithdrawalQueue} from "./interfaces/IWithdrawalQueue.sol";

contract HyperbeatAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Asserts for address;

    bytes4 public constant getAdapterId = bytes4(keccak256("HyperbeatAdapter"));

    IERC20 private immutable i_usdt;
    IERC20 private immutable i_hbUSDT;
    IDepositor private immutable i_depositor;
    IWithdrawalQueue private immutable i_withdrawalQueue;

    constructor(address usdt, address hbUSDT, address depositor, address withdrawalQueue) {
        usdt.assertNotZeroAddress();
        hbUSDT.assertNotZeroAddress();
        depositor.assertNotZeroAddress();
        withdrawalQueue.assertNotZeroAddress();

        i_usdt = IERC20(usdt);
        i_hbUSDT = IERC20(hbUSDT);
        i_depositor = IDepositor(depositor);
        i_withdrawalQueue = IWithdrawalQueue(withdrawalQueue);
    }

    /// @notice Deposit USDT to receive hbUSDT
    /// @param amount Amount of USDT to deposit
    /// @return hbUSDTAmount Amount of hbUSDT received
    function deposit(uint256 amount, bytes32 refCode) external returns (uint256 hbUSDTAmount) {
        hbUSDTAmount = _deposit(i_usdt, amount, refCode);
    }

    /// @notice Deposit all USDT except the given amount
    /// @param except Amount to be left
    /// @return hbUSDTAmount Amount of hbUSDT received
    function depositAllExcept(uint256 except, bytes32 refCode)
        external
        returns (uint256 hbUSDTAmount)
    {
        IERC20 usdt = i_usdt;
        uint256 amount = usdt.balanceOf(msg.sender) - except;
        hbUSDTAmount = _deposit(usdt, amount, refCode);
    }

    /// @notice Instantly withdraws hbUSDT token to USDT
    /// @dev Extra fees applied by Hyperbeat
    /// @param hbUSTAmount Amount of hbUSDT to withdraw
    /// @return withdrawn Amount of USDT redeemed
    function instantWithdraw(uint256 hbUSTAmount) external returns (uint256 withdrawn) {
        return _instantWithdraw(i_hbUSDT, hbUSTAmount);
    }

    /// @notice Instantly withdraws hbUSDT token to USDT except given amount
    /// @dev Extra fees applied by Hyperbeat
    /// @param except Amount of hbUSDT to be left
    /// @return withdrawn Amount of USDT redeemed
    function instantWithdrawAllExcept(uint256 except) external returns (uint256 withdrawn) {
        IERC20 hbUSDT = i_hbUSDT;
        uint256 amount = hbUSDT.balanceOf(msg.sender) - except;
        return _instantWithdraw(hbUSDT, amount);
    }

    function getUSDT() external view returns (address) {
        return address(i_usdt);
    }

    function getHbUSDT() external view returns (address) {
        return address(i_hbUSDT);
    }

    function getHyperbeatDepositor() external view returns (address) {
        return address(i_depositor);
    }

    function getHyperbeatWithdrawalQueue() external view returns (address) {
        return address(i_withdrawalQueue);
    }

    function _deposit(IERC20 usdt, uint256 amount, bytes32 refCode)
        private
        returns (uint256 hbUSDTAmount)
    {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(usdt), amount);

        IDepositor depositor = i_depositor;
        usdt.forceApprove(address(depositor), amount);
        depositor.deposit(address(usdt), address(this), amount, refCode);

        hbUSDTAmount = _transferAll(i_hbUSDT);

        emit Swap(msg.sender, address(usdt), amount, address(i_hbUSDT), hbUSDTAmount);
    }

    function _instantWithdraw(IERC20 hbUSDT, uint256 hbUSDTAmount) private returns (uint256 withdrawn) {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(hbUSDT), hbUSDTAmount);
        
        IWithdrawalQueue withdrawalQueue = i_withdrawalQueue;
        hbUSDT.forceApprove(address(withdrawalQueue), hbUSDTAmount);

        withdrawalQueue.instantWithdraw(address(this), hbUSDTAmount);
        withdrawn = _transferAll(i_usdt);
    
        emit Swap(msg.sender, address(hbUSDT), hbUSDTAmount, address(i_usdt), withdrawn);
    }

    function _transferAll(IERC20 token) private returns (uint256 transferAmount) {
        transferAmount = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, transferAmount);
    }
}
