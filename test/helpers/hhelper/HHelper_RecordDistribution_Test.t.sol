// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    HAsset,
    HInvestment,
    HInvestmentPayoutsHistory,
    HInvestorPayout,
    HInvestorPayoutsHistory,
    HOwnerPayout,
    HOwnerPayoutsHistory,
    HPayoutType,
    HSharingBreakdown,
    USDC_UNIT
} from "../../../src/types/common.sol";
import {HHelper} from "../../../src/helpers/HHelper.sol";

/// @title Tests for {HHelper.recordDistribution}.
/// @notice The helper writes the accounting for one payment split across the owner and the
///         senior/junior pools, and moves no tokens. It appends one owner payout, an equal-share
///         payout per investor in each non-empty tier, and bumps the per-investor, aggregate and
///         platform histories. Every USD amount is in USDC base units (6 decimals).
contract HHelperRecordDistributionTest is Test, HHelper {
    bytes32 internal constant ASSET_ID = bytes32("keke-0001");
    bytes32 internal constant INVESTMENT_ID = bytes32("inv-0001");
    address internal constant SENIOR_ONE = address(0x5111);
    address internal constant SENIOR_TWO = address(0x5222);
    address internal constant JUNIOR_ONE = address(0x7111);

    constructor() HHelper(address(this), IERC20(address(0))) {}

    function setUp() public {
        _seedAsset();
        _seedInvestment();
    }

    function _seedAsset() internal {
        HAsset memory asset = HAsset({
            id: ASSET_ID,
            active: true,
            name: bytes32("Keke"),
            costPrice: 125 * USDC_UNIT,
            sellPrice: 205 * USDC_UNIT,
            oneSeniorInvestorBuyingPrice: 100 * USDC_UNIT,
            oneSeniorInvestorProfit: 5 * USDC_UNIT,
            oneJuniorInvestorBuyingPrice: 25 * USDC_UNIT,
            oneJuniorInvestorProfit: 5 * USDC_UNIT,
            riderSlashableRepayableExtraCharge: 2 * USDC_UNIT,
            ownerProfit: 70 * USDC_UNIT,
            sharingPercentSeniorInvestor: 70,
            sharingPercentJuniorInvestor: 25,
            sharingPercentOwner: 5,
            sharingPercentJuniorInvestorAfterSeniorPaid: 60,
            sharingPercentOwnerAfterSeniorPaid: 40,
            totalNumberOfSeniorInvestorsNeeded: 2,
            totalNumberOfJuniorInvestorsNeeded: 1
        });
        assetsList.push(asset);
        assets[ASSET_ID] = assetsList.length;
    }

    function _seedInvestment() internal {
        HInvestment storage investment = investmentsList.push();
        investment.investmentId = INVESTMENT_ID;
        investment.assetId = ASSET_ID;
        investment.seniorInvestorsList.push(SENIOR_ONE);
        investment.seniorInvestorsList.push(SENIOR_TWO);
        investment.juniorInvestorsList.push(JUNIOR_ONE);
        investments[INVESTMENT_ID] = investmentsList.length;
    }

    function _breakdown(uint256 ownerAmount, uint256 seniorAmount, uint256 juniorAmount)
        internal
        pure
        returns (HSharingBreakdownLocal memory)
    {
        return HSharingBreakdownLocal({ownerAmount: ownerAmount, seniorAmount: seniorAmount, juniorAmount: juniorAmount});
    }

    /// @dev Minimal mirror of the shared struct so tests can build a breakdown inline.
    struct HSharingBreakdownLocal {
        uint256 ownerAmount;
        uint256 seniorAmount;
        uint256 juniorAmount;
    }

    function _record(HSharingBreakdownLocal memory b, HPayoutType payoutType) internal {
        HSharingBreakdown memory breakdown = HSharingBreakdown({
            ownerAmount: b.ownerAmount,
            seniorInvestorsAmount: b.seniorAmount,
            juniorInvestorsAmount: b.juniorAmount
        });
        recordDistribution(getInvestmentStorage(INVESTMENT_ID), INVESTMENT_ID, breakdown, payoutType);
    }

    //<editor-fold desc="Owner accounting">

    function test_RecordDistribution_AppendsOwnerPayout_AndHistory() public {
        _record(_breakdown(5 * USDC_UNIT, 100 * USDC_UNIT, 25 * USDC_UNIT), HPayoutType.RiderPaying);

        assertEq(ownerPayoutsList.length, 1);
        HOwnerPayout memory payout = ownerPayoutsList[0];
        assertEq(payout.investmentId, INVESTMENT_ID);
        assertEq(payout.amountPaid, 5 * USDC_UNIT);
        assertEq(payout.timePaid, block.timestamp);
        assertEq(payout.addressPaidInto, owner());
        assertEq(uint256(payout.payoutType), uint256(HPayoutType.RiderPaying));

        assertEq(ownerPayouts[INVESTMENT_ID], 1);

        HOwnerPayoutsHistory memory history = ownerPayoutHistory[INVESTMENT_ID];
        assertEq(history.totalAmountPaid, 5 * USDC_UNIT);
        assertEq(history.totalNumberOfTimesPaid, 1);
    }

    function test_RecordDistribution_SkipsOwnerPayout_WhenOwnerShareIsZero() public {
        _record(_breakdown(0, 100 * USDC_UNIT, 25 * USDC_UNIT), HPayoutType.RiderPaying);

        assertEq(ownerPayoutsList.length, 0);
        assertEq(ownerPayouts[INVESTMENT_ID], 0);
        assertEq(ownerPayoutHistory[INVESTMENT_ID].totalNumberOfTimesPaid, 0);
    }

    //</editor-fold desc="Owner accounting">

    //<editor-fold desc="Investor accounting">

    function test_RecordDistribution_SplitsEachTierEqually_AcrossItsInvestors() public {
        _record(_breakdown(5 * USDC_UNIT, 100 * USDC_UNIT, 25 * USDC_UNIT), HPayoutType.RiderPaying);

        assertEq(investorPayoutList.length, 3);

        HInvestorPayout memory seniorOne = investorPayoutList[0];
        assertEq(seniorOne.addressPaidInto, SENIOR_ONE);
        assertEq(seniorOne.amountPaid, 50 * USDC_UNIT);

        HInvestorPayout memory seniorTwo = investorPayoutList[1];
        assertEq(seniorTwo.addressPaidInto, SENIOR_TWO);
        assertEq(seniorTwo.amountPaid, 50 * USDC_UNIT);

        HInvestorPayout memory juniorOne = investorPayoutList[2];
        assertEq(juniorOne.addressPaidInto, JUNIOR_ONE);
        assertEq(juniorOne.amountPaid, 25 * USDC_UNIT);

        HInvestment storage investment = getInvestmentStorage(INVESTMENT_ID);
        assertEq(investment.investorPayoutHistory[SENIOR_ONE].totalAmountPaid, 50 * USDC_UNIT);
        assertEq(investment.investorPayoutHistory[SENIOR_TWO].totalAmountPaid, 50 * USDC_UNIT);
        assertEq(investment.investorPayoutHistory[JUNIOR_ONE].totalAmountPaid, 25 * USDC_UNIT);
        assertEq(investment.investorPayoutHistory[SENIOR_ONE].totalNumberOfTimesPaid, 1);

        assertEq(investorPayouts[SENIOR_ONE][INVESTMENT_ID], 1);
        assertEq(investorPayouts[SENIOR_TWO][INVESTMENT_ID], 2);
        assertEq(investorPayouts[JUNIOR_ONE][INVESTMENT_ID], 3);
    }

    /// @notice A pool split that does not divide evenly rounds each investor down; the remainder
    ///         stays in the contract. The recorded histories still count the whole pool amount,
    ///         matching the documented design where the remainder is not redistributed.
    function test_RecordDistribution_LeavesRemainderInContract_WhenPoolDoesNotDivideEvenly() public {
        _record(_breakdown(0, 101, 0), HPayoutType.RiderPaying);

        assertEq(investorPayoutList.length, 2);
        assertEq(investorPayoutList[0].amountPaid, 50);
        assertEq(investorPayoutList[1].amountPaid, 50);

        HInvestment storage investment = getInvestmentStorage(INVESTMENT_ID);
        assertEq(investment.investorPayoutHistory[SENIOR_ONE].totalAmountPaid, 50);
        assertEq(investment.investorPayoutHistory[SENIOR_TWO].totalAmountPaid, 50);

        // The aggregate history records the full pool, not the 100 actually credited.
        assertEq(investment.investmentPayoutHistory.totalAmountPaid, 101);
        assertEq(stats.totalSeniorPayoutsUsd, 101);
    }

    function test_RecordDistribution_SkipsEmptyTier() public {
        // Fresh investment with only a senior investor.
        bytes32 onlySeniorId = bytes32("inv-only-senior");
        HInvestment storage onlySenior = investmentsList.push();
        onlySenior.investmentId = onlySeniorId;
        onlySenior.assetId = ASSET_ID;
        onlySenior.seniorInvestorsList.push(SENIOR_ONE);
        investments[onlySeniorId] = investmentsList.length;

        HSharingBreakdown memory breakdown =
            HSharingBreakdown({ownerAmount: 0, seniorInvestorsAmount: 10, juniorInvestorsAmount: 90});
        recordDistribution(onlySenior, onlySeniorId, breakdown, HPayoutType.RiderPaying);

        // Only the senior entry exists; the empty junior pool creates nothing.
        assertEq(investorPayoutList.length, 1);
        assertEq(investorPayoutList[0].addressPaidInto, SENIOR_ONE);
        assertEq(investorPayoutList[0].amountPaid, 10);
    }

    //</editor-fold desc="Investor accounting">

    //<editor-fold desc="Aggregate accounting">

    function test_RecordDistribution_UpdatesInvestmentHistory() public {
        _record(_breakdown(5 * USDC_UNIT, 100 * USDC_UNIT, 25 * USDC_UNIT), HPayoutType.RiderPaying);

        HInvestmentPayoutsHistory memory history = getInvestmentStorage(INVESTMENT_ID).investmentPayoutHistory;
        assertEq(history.investmentId, INVESTMENT_ID);
        assertEq(history.totalAmountPaid, 130 * USDC_UNIT);
        assertEq(history.totalNumberOfTimesPaid, 1);
    }

    function test_RecordDistribution_AccumulatesAcrossDistributions() public {
        _record(_breakdown(5 * USDC_UNIT, 100 * USDC_UNIT, 25 * USDC_UNIT), HPayoutType.RiderPaying);
        _record(_breakdown(4 * USDC_UNIT, 0, 6 * USDC_UNIT), HPayoutType.RiderSavingsSlash);

        HInvestment storage investment = getInvestmentStorage(INVESTMENT_ID);
        assertEq(investment.investmentPayoutHistory.totalAmountPaid, 140 * USDC_UNIT);
        assertEq(investment.investmentPayoutHistory.totalNumberOfTimesPaid, 2);

        assertEq(ownerPayoutsList.length, 2);
        assertEq(ownerPayoutHistory[INVESTMENT_ID].totalAmountPaid, 9 * USDC_UNIT);
        assertEq(ownerPayoutHistory[INVESTMENT_ID].totalNumberOfTimesPaid, 2);

        // Second distribution: senior skipped, junior gets 6, one owner entry.
        assertEq(investorPayoutList.length, 4);
        assertEq(investorPayoutList[3].addressPaidInto, JUNIOR_ONE);
        assertEq(investorPayoutList[3].amountPaid, 6 * USDC_UNIT);
    }

    function test_RecordDistribution_UpdatesPlatformStats() public {
        _record(_breakdown(5 * USDC_UNIT, 100 * USDC_UNIT, 25 * USDC_UNIT), HPayoutType.RiderPaying);

        assertEq(stats.totalOwnerPayoutsUsd, 5 * USDC_UNIT);
        assertEq(stats.totalSeniorPayoutsUsd, 100 * USDC_UNIT);
        assertEq(stats.totalJuniorPayoutsUsd, 25 * USDC_UNIT);
    }

    function test_RecordDistribution_StoresRequestedPayoutType() public {
        _record(_breakdown(5 * USDC_UNIT, 100 * USDC_UNIT, 25 * USDC_UNIT), HPayoutType.RiderSavingsSlash);

        assertEq(uint256(ownerPayoutsList[0].payoutType), uint256(HPayoutType.RiderSavingsSlash));
        assertEq(uint256(investorPayoutList[0].payoutType), uint256(HPayoutType.RiderSavingsSlash));
        assertEq(uint256(investorPayoutList[2].payoutType), uint256(HPayoutType.RiderSavingsSlash));
    }

    //</editor-fold desc="Aggregate accounting">
}
