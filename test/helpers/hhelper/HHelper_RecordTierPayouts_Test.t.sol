// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HInvestment, HInvestorPayout, HPayoutType, USDC_UNIT} from "../../../src/types/common.sol";
import {HHelper} from "../../../src/helpers/HHelper.sol";
import {HenriableVehicleNFT} from "../../../src/HenriableVehicleNFT.sol";

/// @title Tests for {HHelper.recordTierPayouts}.
/// @notice The helper appends one equal-share payout per investor in a tier and updates each
///         investor's payout history. An empty tier or a zero pool records nothing; a pool that
///         does not divide evenly leaves the remainder uncounted in the individual entries.
///         Every USD amount is in USDC base units (6 decimals).
contract HHelperRecordTierPayoutsTest is Test, HHelper {
    bytes32 internal constant INVESTMENT_ID = bytes32("inv-0001");
    address internal constant INVESTOR_ONE = address(0x5111);
    address internal constant INVESTOR_TWO = address(0x5222);

    constructor() HHelper(address(this), IERC20(address(0)), new HenriableVehicleNFT(address(this))) {}

    function setUp() public {
        HInvestment storage investment = investmentsList.push();
        investment.investmentId = INVESTMENT_ID;
        investments[INVESTMENT_ID] = investmentsList.length;
    }

    function _addInvestor(address investor) internal {
        HInvestment storage investment = getInvestmentStorage(INVESTMENT_ID);
        investment.seniorInvestorsList.push(investor);
        investment.seniorInvestors[investor] = investment.seniorInvestorsList.length;
    }

    function _record(uint256 poolAmount, HPayoutType payoutType) internal {
        HInvestment storage investment = getInvestmentStorage(INVESTMENT_ID);
        recordTierPayouts(investment, INVESTMENT_ID, investment.seniorInvestorsList, poolAmount, payoutType);
    }

    function test_RecordTierPayouts_RecordsNothing_WhenTierIsEmpty() public {
        _record(100 * USDC_UNIT, HPayoutType.RiderPaying);

        assertEq(investorPayoutList.length, 0);
    }

    function test_RecordTierPayouts_RecordsNothing_WhenPoolAmountIsZero() public {
        _addInvestor(INVESTOR_ONE);

        _record(0, HPayoutType.RiderPaying);

        assertEq(investorPayoutList.length, 0);
        assertEq(getInvestmentStorage(INVESTMENT_ID).investorPayoutHistory[INVESTOR_ONE].totalNumberOfTimesPaid, 0);
    }

    function test_RecordTierPayouts_SplitsPoolEqually_AcrossInvestors() public {
        _addInvestor(INVESTOR_ONE);
        _addInvestor(INVESTOR_TWO);

        _record(100 * USDC_UNIT, HPayoutType.RiderPaying);

        assertEq(investorPayoutList.length, 2);
        HInvestorPayout memory first = investorPayoutList[0];
        assertEq(first.investmentId, INVESTMENT_ID);
        assertEq(first.addressPaidInto, INVESTOR_ONE);
        assertEq(first.amountPaid, 50 * USDC_UNIT);
        assertEq(first.timePaid, block.timestamp);
        assertEq(uint256(first.payoutType), uint256(HPayoutType.RiderPaying));

        HInvestorPayout memory second = investorPayoutList[1];
        assertEq(second.addressPaidInto, INVESTOR_TWO);
        assertEq(second.amountPaid, 50 * USDC_UNIT);

        assertEq(investorPayouts[INVESTOR_ONE][INVESTMENT_ID], 1);
        assertEq(investorPayouts[INVESTOR_TWO][INVESTMENT_ID], 2);
    }

    function test_RecordTierPayouts_UpdatesEachInvestorHistory() public {
        _addInvestor(INVESTOR_ONE);
        _addInvestor(INVESTOR_TWO);

        _record(100 * USDC_UNIT, HPayoutType.RiderPaying);

        HInvestment storage investment = getInvestmentStorage(INVESTMENT_ID);
        assertEq(investment.investorPayoutHistory[INVESTOR_ONE].investorAddress, INVESTOR_ONE);
        assertEq(investment.investorPayoutHistory[INVESTOR_ONE].investmentId, INVESTMENT_ID);
        assertEq(investment.investorPayoutHistory[INVESTOR_ONE].totalAmountPaid, 50 * USDC_UNIT);
        assertEq(investment.investorPayoutHistory[INVESTOR_ONE].totalNumberOfTimesPaid, 1);
        assertEq(investment.investorPayoutHistory[INVESTOR_TWO].totalAmountPaid, 50 * USDC_UNIT);
        assertEq(investment.investorPayoutHistory[INVESTOR_TWO].totalNumberOfTimesPaid, 1);
    }

    function test_RecordTierPayouts_AccumulatesHistory_AcrossCalls() public {
        _addInvestor(INVESTOR_ONE);

        _record(50 * USDC_UNIT, HPayoutType.RiderPaying);
        _record(30 * USDC_UNIT, HPayoutType.RiderSavingsSlash);

        HInvestment storage investment = getInvestmentStorage(INVESTMENT_ID);
        assertEq(investment.investorPayoutHistory[INVESTOR_ONE].totalAmountPaid, 80 * USDC_UNIT);
        assertEq(investment.investorPayoutHistory[INVESTOR_ONE].totalNumberOfTimesPaid, 2);
        assertEq(investorPayoutList.length, 2);
    }

    /// @notice A pool that does not divide evenly credits each investor the floored share; the
    ///         remainder is not recorded on any investor entry.
    function test_RecordTierPayouts_FloorsShare_WhenPoolDoesNotDivideEvenly() public {
        _addInvestor(INVESTOR_ONE);
        _addInvestor(INVESTOR_TWO);

        _record(101, HPayoutType.RiderPaying);

        assertEq(investorPayoutList.length, 2);
        assertEq(investorPayoutList[0].amountPaid, 50);
        assertEq(investorPayoutList[1].amountPaid, 50);

        HInvestment storage investment = getInvestmentStorage(INVESTMENT_ID);
        assertEq(investment.investorPayoutHistory[INVESTOR_ONE].totalAmountPaid, 50);
        assertEq(investment.investorPayoutHistory[INVESTOR_TWO].totalAmountPaid, 50);
    }

    function test_RecordTierPayouts_StoresRequestedPayoutType() public {
        _addInvestor(INVESTOR_ONE);

        _record(10 * USDC_UNIT, HPayoutType.RiderSavingsSlash);

        assertEq(uint256(investorPayoutList[0].payoutType), uint256(HPayoutType.RiderSavingsSlash));
    }
}
