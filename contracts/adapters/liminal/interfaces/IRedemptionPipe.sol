// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IRedemptionPipe {
    /**
     * @param shares Amount of shares to redeem (18 decimals)
     * @param receiver Address to receive assets
     * @param controller Address that owns the shares
     * @return assets Amount of assets received (underlying decimals, after fees)
     */
    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets);

    /**
     * @param shares Amount of shares to redeem (18 decimals)
     * @param controller Address that will control the redemption
     * @param owner Address that owns shares
     * @return requestId Always returns 0
     */
    function requestRedeem(
        uint256 shares,
        address receiver,
        address controller,
        address owner
    ) external returns (uint256 requestId);

    /**
     * @param owner Owner address
     * @return shares Amount of pending shares
     */
    function pendingRedeemRequest(address owner)
        external
        view
        returns (uint256 shares);

    function fulfillRedeems(address[] calldata owners, uint256[] calldata shares) external;
}