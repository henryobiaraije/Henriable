// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HAsset} from "../../../src/types/common.sol";
import {HHelper} from "../../../src/helpers/HHelper.sol";

/// @title Tests for {HHelper.isAssetSettingsCorrect}.
/// @notice Exercises the asset pricing accuracy check. The check passes when the investor
///         pools cover the asset cost price and the rider's sell price covers the investor
///         principal, their profits and the owner's profit. The rider's slashable savings
///         charge is charged on top of the sell price and is excluded.
contract HHelperIsAssetSettingsCorrectTest is Test, HHelper {
    constructor() HHelper(address(this), IERC20(address(0))) {}

    /// @notice Builds a correct Keke asset from the worked example: a 1,000 cost price
    ///         covered by 500 of senior buying and 500 of junior buying, 125 of total
    ///         investor profit and 75 of owner profit, so the minimum sell price is 1,200.
    function correctAsset() internal pure returns (HAsset memory asset) {
        asset = HAsset({
            id: bytes32("keke-0001"),
            active: true,
            name: bytes32("Keke"),
            costPrice: 1_000,
            sellPrice: 1_200,
            oneSeniorInvestorBuyingPrice: 100,
            oneSeniorInvestorProfit: 5,
            oneJuniorInvestorBuyingPrice: 25,
            oneJuniorInvestorProfit: 5,
            riderSlashableRepayableExtraCharge: 2,
            ownerProfit: 75,
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
        asset.sellPrice = 1_500;
        assertTrue(isAssetSettingsCorrect(asset));
    }

    function test_IsAssetSettingsCorrect_ReturnsFalse_WhenSellPriceBelowPayouts() public pure {
        HAsset memory asset = correctAsset();
        asset.sellPrice = 1_199;
        assertFalse(isAssetSettingsCorrect(asset));
    }

    function test_IsAssetSettingsCorrect_ReturnsFalse_WhenOwnerProfitIsUncovered() public pure {
        HAsset memory asset = correctAsset();
        asset.ownerProfit = 100;
        assertFalse(isAssetSettingsCorrect(asset));
    }

    function test_IsAssetSettingsCorrect_ReturnsFalse_WhenInvestorBuyingUnderFundsCostPrice() public pure {
        HAsset memory asset = correctAsset();
        asset.costPrice = 2_000;
        asset.sellPrice = 2_125;
        assertFalse(isAssetSettingsCorrect(asset));
    }

    function test_IsAssetSettingsCorrect_ReturnsTrue_WhenInvestorBuyingExceedsCostPrice() public pure {
        HAsset memory asset = correctAsset();
        asset.costPrice = 500;
        assertTrue(isAssetSettingsCorrect(asset));
    }

    function test_IsAssetSettingsCorrect_ReturnsFalse_WhenJuniorProfitIsUncovered() public pure {
        HAsset memory asset = correctAsset();
        asset.oneJuniorInvestorProfit = 10;
        assertFalse(isAssetSettingsCorrect(asset));
    }

    function test_IsAssetSettingsCorrect_ReturnsTrue_WhenSeniorPoolIsEmptyAndJuniorCoversAll() public pure {
        HAsset memory asset = correctAsset();
        asset.oneSeniorInvestorBuyingPrice = 0;
        asset.oneSeniorInvestorProfit = 0;
        asset.totalNumberOfSeniorInvestorsNeeded = 0;
        asset.oneJuniorInvestorBuyingPrice = 50;
        asset.totalNumberOfJuniorInvestorsNeeded = 20;
        assertTrue(isAssetSettingsCorrect(asset));
    }

    function test_IsAssetSettingsCorrect_IgnoresRiderSavingsCharge() public pure {
        HAsset memory asset = correctAsset();
        asset.riderSlashableRepayableExtraCharge = 1_000;
        assertTrue(isAssetSettingsCorrect(asset));
    }
}
