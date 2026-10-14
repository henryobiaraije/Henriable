// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HAsset, HInvestment, USDC_UNIT} from "../../../src/types/common.sol";
import {HHelper} from "../../../src/helpers/HHelper.sol";

/// @title Tests for {HHelper.calcRiderAmountToPayNow}.
/// @notice The helper returns the next instalment the rider owes: the periodic minimum,
///         capped by the outstanding balance on the final instalment, PLUS the asset's
///         per-period savings charge. The savings charge is always added on top, so for a
///         $0.6594 minimum and a $0.14 savings charge the first instalment is $0.7994
///         (~$0.80), not $0.66. Every amount is in USDC base units (6 decimals).
/// @dev    Values mirror the reported live case: minimum 659_400, savings charge 140_000.
contract HHelperCalcRiderAmountToPayNowTest is Test, HHelper {
    bytes32 internal constant ASSET_ID = bytes32("keke-0001");
    bytes32 internal constant INVESTMENT_ID = bytes32("inv-0001");
    address internal constant RIDER = address(0xB0B);

    uint256 internal constant SELL_PRICE = 1_200 * USDC_UNIT;
    uint256 internal constant MINIMUM_PAYMENT = 659_400;
    uint256 internal constant SAVINGS_CHARGE = 140_000;
    uint256 internal constant EXPECTED_FIRST_INSTALMENT = MINIMUM_PAYMENT + SAVINGS_CHARGE;

    constructor() HHelper(address(this), IERC20(address(0))) {}

    function setUp() public {
        HAsset memory asset = HAsset({
            id: ASSET_ID,
            active: true,
            name: bytes32("Keke"),
            costPrice: 1_000 * USDC_UNIT,
            sellPrice: SELL_PRICE,
            oneSeniorInvestorBuyingPrice: 100 * USDC_UNIT,
            oneSeniorInvestorProfit: 5 * USDC_UNIT,
            oneJuniorInvestorBuyingPrice: 25 * USDC_UNIT,
            oneJuniorInvestorProfit: 5 * USDC_UNIT,
            riderSlashableRepayableExtraCharge: SAVINGS_CHARGE,
            ownerProfit: 75 * USDC_UNIT,
            sharingPercentSeniorInvestor: 70,
            sharingPercentJuniorInvestor: 25,
            sharingPercentOwner: 5,
            sharingPercentJuniorInvestorAfterSeniorPaid: 60,
            sharingPercentOwnerAfterSeniorPaid: 40,
            totalNumberOfSeniorInvestorsNeeded: 5,
            totalNumberOfJuniorInvestorsNeeded: 20
        });
        assetsList.push(asset);
        assets[ASSET_ID] = assetsList.length;

        HInvestment storage investment = investmentsList.push();
        investment.investmentId = INVESTMENT_ID;
        investment.assetId = ASSET_ID;
        investment.minimumRiderPeriodicPayingsUsd = MINIMUM_PAYMENT;
        investment.riderWhoHiredIt = RIDER;
        investments[INVESTMENT_ID] = investmentsList.length;
    }

    function amountDue() internal view returns (uint256) {
        return calcRiderAmountToPayNow(getInvestmentStorage(INVESTMENT_ID), getAssetStorage(ASSET_ID));
    }

    function setAmountPaid(uint256 amount) internal {
        getInvestmentStorage(INVESTMENT_ID).riderPayinsHistory.totalAmountPaid = amount;
    }

    //<editor-fold desc="Happy path">

    /// @notice Reproduces the reported case: a $0.6594 periodic minimum plus the $0.14
    ///         savings charge yields $0.7994 (~$0.80), never the bare $0.66 minimum.
    function test_CalcRiderAmountToPayNow_ReturnsMinimumPlusSavings_WhenFirstInstalment() public view {
        assertEq(amountDue(), EXPECTED_FIRST_INSTALMENT);
        assertEq(amountDue(), 799_400);
    }

    function test_CalcRiderAmountToPayNow_ReturnsMinimumPlusSavings_WhenBalanceEqualsMinimum() public {
        setAmountPaid(SELL_PRICE - MINIMUM_PAYMENT);

        assertEq(amountDue(), EXPECTED_FIRST_INSTALMENT);
    }

    function test_CalcRiderAmountToPayNow_ReturnsRemainingPlusSavings_WhenBalanceBelowMinimum() public {
        setAmountPaid(SELL_PRICE - 500_000);

        assertEq(amountDue(), 500_000 + SAVINGS_CHARGE);
    }

    function test_CalcRiderAmountToPayNow_AddsSavingsCharge_OnTopOfCappedBalance() public {
        setAmountPaid(SELL_PRICE - 1);

        assertEq(amountDue(), 1 + SAVINGS_CHARGE);
    }

    function test_CalcRiderAmountToPayNow_MatchesGetter_WhenFullBalanceOutstanding() public {
        vm.prank(RIDER);
        uint256 viaGetter = this.getRiderAmountToPayNow(INVESTMENT_ID);

        assertEq(viaGetter, amountDue());
    }

    //</editor-fold desc="Happy path">

    //<editor-fold desc="Edge cases">

    /// @notice Characterises the fully-paid branch: with nothing outstanding the capped
    ///         instalment is 0, so only the savings charge remains. This branch is not
    ///         reachable through the guarded callers ({Henriable.actionRiderPayin} reverts
    ///         first, and {HHelper.getRiderAmountToPayNow} returns 0), so it does not affect
    ///         the public API.
    function test_CalcRiderAmountToPayNow_ReturnsSavingsCharge_WhenFullyPaid() public {
        setAmountPaid(SELL_PRICE);

        assertEq(amountDue(), SAVINGS_CHARGE);
    }

    function test_CalcRiderAmountToPayNow_ReturnsSavingsCharge_WhenOverpaid() public {
        setAmountPaid(SELL_PRICE + 100 * USDC_UNIT);

        assertEq(amountDue(), SAVINGS_CHARGE);
    }

    //</editor-fold desc="Edge cases">
}
