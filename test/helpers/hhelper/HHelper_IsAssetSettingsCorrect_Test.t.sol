// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HAsset, USDC_UNIT} from "../../../src/types/common.sol";
import {HHelper} from "../../../src/helpers/HHelper.sol";

/// @title Tests for {HHelper.isAssetSettingsCorrect}.
/// @notice Exercises the asset pricing accuracy check. The check passes when the investor
///         pools cover the asset cost price and the rider's sell price covers the investor
///         principal, their profits and the owner's profit. The rider's slashable savings
///         charge is charged on top of the sell price and is excluded. Every USD amount is
///         expressed in USDC base units (6 decimals), so a whole-dollar figure is written
///         as `<dollars> * USDC_UNIT`.
contract HHelperIsAssetSettingsCorrectTest is Test, HHelper {
    constructor() HHelper(address(this), IERC20(address(0))) {}

    /// @notice Builds a correct Keke asset from the worked example: a $1,000 cost price
    ///         covered by $500 of senior buying and $500 of junior buying, $125 of total
    ///         investor profit and $75 of owner profit, so the minimum sell price is $1,200.
    /// @dev    The dollar amounts are scaled to USDC base units; the percentages and slot
    ///         counts are not amounts and stay unscaled.
    function correctAsset() internal pure returns (HAsset memory asset) {
        asset = HAsset({
            id: bytes32("keke-0001"),
            active: true,
            name: bytes32("Keke"),
            costPrice: 1_000 * USDC_UNIT,
            sellPrice: 1_200 * USDC_UNIT,
            oneSeniorInvestorBuyingPrice: 100 * USDC_UNIT,
            oneSeniorInvestorProfit: 5 * USDC_UNIT,
            oneJuniorInvestorBuyingPrice: 25 * USDC_UNIT,
            oneJuniorInvestorProfit: 5 * USDC_UNIT,
            riderSlashableRepayableExtraCharge: 2 * USDC_UNIT,
            ownerProfit: 75 * USDC_UNIT,
            sharingPercentSeniorInvestor: 70,
            sharingPercentJuniorInvestor: 25,
            sharingPercentOwner: 5,
            sharingPercentJuniorInvestorAfterSeniorPaid: 60,
            sharingPercentOwnerAfterSeniorPaid: 40,
            totalNumberOfSeniorInvestorsNeeded: 5,
            totalNumberOfJuniorInvestorsNeeded: 20
        });
    }

    function test_IsAssetSettingsCorrect_ReturnsTrue_WhenSellPriceExactlyCoversPayouts() public pure {
        HAsset memory asset = correctAsset();
        assertTrue(isAssetSettingsCorrect(asset));
    }

    function test_IsAssetSettingsCorrect_ReturnsTrue_WhenSellPriceExceedsPayouts() public pure {
        HAsset memory asset = correctAsset();
        asset.sellPrice = 1_500 * USDC_UNIT;
        assertTrue(isAssetSettingsCorrect(asset));
    }

    function test_IsAssetSettingsCorrect_ReturnsFalse_WhenSellPriceBelowPayouts() public pure {
        HAsset memory asset = correctAsset();
        asset.sellPrice = 1_199 * USDC_UNIT;
        assertFalse(isAssetSettingsCorrect(asset));
    }

    function test_IsAssetSettingsCorrect_ReturnsFalse_WhenOwnerProfitIsUncovered() public pure {
        HAsset memory asset = correctAsset();
        asset.ownerProfit = 100 * USDC_UNIT;
        assertFalse(isAssetSettingsCorrect(asset));
    }

    function test_IsAssetSettingsCorrect_ReturnsFalse_WhenInvestorBuyingUnderFundsCostPrice() public pure {
        HAsset memory asset = correctAsset();
        asset.costPrice = 2_000 * USDC_UNIT;
        asset.sellPrice = 2_125 * USDC_UNIT;
        assertFalse(isAssetSettingsCorrect(asset));
    }

    function test_IsAssetSettingsCorrect_ReturnsTrue_WhenInvestorBuyingExceedsCostPrice() public pure {
        HAsset memory asset = correctAsset();
        asset.costPrice = 500 * USDC_UNIT;
        assertTrue(isAssetSettingsCorrect(asset));
    }

    function test_IsAssetSettingsCorrect_ReturnsFalse_WhenJuniorProfitIsUncovered() public pure {
        HAsset memory asset = correctAsset();
        asset.oneJuniorInvestorProfit = 10 * USDC_UNIT;
        assertFalse(isAssetSettingsCorrect(asset));
    }

    function test_IsAssetSettingsCorrect_ReturnsTrue_WhenSeniorPoolIsEmptyAndJuniorCoversAll() public pure {
        HAsset memory asset = correctAsset();
        asset.oneSeniorInvestorBuyingPrice = 0;
        asset.oneSeniorInvestorProfit = 0;
        asset.totalNumberOfSeniorInvestorsNeeded = 0;
        asset.oneJuniorInvestorBuyingPrice = 50 * USDC_UNIT;
        asset.totalNumberOfJuniorInvestorsNeeded = 20;
        assertTrue(isAssetSettingsCorrect(asset));
    }

    function test_IsAssetSettingsCorrect_IgnoresRiderSavingsCharge() public pure {
        HAsset memory asset = correctAsset();
        asset.riderSlashableRepayableExtraCharge = 1_000 * USDC_UNIT;
        assertTrue(isAssetSettingsCorrect(asset));
    }

    /// @notice Confirms the canonical unit: a configured $14 sell price is 14_000_000 base
    ///         units (6 decimals), and an asset priced so the sell price exactly covers the
    ///         payouts is accepted at that granularity.
    function test_IsAssetSettingsCorrect_TreatsDollarsAsUsdcBaseUnits() public pure {
        assertEq(14 * USDC_UNIT, 14_000_000);

        // $10 cost covered by $4 senior + $6 junior buying, with $1 + $2 investor profit
        // and $1 owner profit, so the $14 sell price exactly covers the total payout.
        HAsset memory asset = HAsset({
            id: bytes32("keke-14"),
            active: true,
            name: bytes32("Keke-14"),
            costPrice: 10_000_000,
            sellPrice: 14_000_000,
            oneSeniorInvestorBuyingPrice: 4_000_000,
            oneSeniorInvestorProfit: 1_000_000,
            oneJuniorInvestorBuyingPrice: 6_000_000,
            oneJuniorInvestorProfit: 2_000_000,
            riderSlashableRepayableExtraCharge: 140_000,
            ownerProfit: 1_000_000,
            sharingPercentSeniorInvestor: 70,
            sharingPercentJuniorInvestor: 25,
            sharingPercentOwner: 5,
            sharingPercentJuniorInvestorAfterSeniorPaid: 60,
            sharingPercentOwnerAfterSeniorPaid: 40,
            totalNumberOfSeniorInvestorsNeeded: 1,
            totalNumberOfJuniorInvestorsNeeded: 1
        });

        assertEq(asset.sellPrice, 14_000_000);
        assertTrue(isAssetSettingsCorrect(asset));
    }
}
