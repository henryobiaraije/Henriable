// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HInvestment, HRiderSavings, HRiderSavingsHistory, USDC_UNIT} from "../../../src/types/common.sol";
import {HHelper} from "../../../src/helpers/HHelper.sol";
import {HenriableVehicleNFT} from "../../../src/HenriableVehicleNFT.sol";

/// @title Tests for {HHelper.recordRiderSavings}.
/// @notice The helper accumulates the rider's refundable savings for an investment: it bumps the
///         running total, tracking it as held in the contract, and appends a timestamped entry.
///         A zero amount is a no-op. Every USD amount is in USDC base units (6 decimals).
contract HHelperRecordRiderSavingsTest is Test, HHelper {
    bytes32 internal constant INVESTMENT_ID = bytes32("inv-0001");
    address internal constant RIDER = address(0xB1DE);

    constructor() HHelper(address(this), IERC20(address(0)), new HenriableVehicleNFT(address(this))) {}

    function setUp() public {
        HInvestment storage investment = investmentsList.push();
        investment.investmentId = INVESTMENT_ID;
        investment.riderWhoHiredIt = RIDER;
        investments[INVESTMENT_ID] = investmentsList.length;
    }

    function _record(uint256 amount) internal {
        recordRiderSavings(getInvestmentStorage(INVESTMENT_ID), amount);
    }

    function test_RecordRiderSavings_RecordsNothing_WhenAmountIsZero() public {
        _record(0);

        HRiderSavingsHistoryView memory savings = _savings();
        assertEq(savings.totalAmountSaved, 0);
        assertEq(savings.entries, 0);
        assertEq(stats.riderSavingsHeldUsd, 0);
    }

    function test_RecordRiderSavings_AddsEntry_AndTracksHeldAmount() public {
        _record(2 * USDC_UNIT);

        HRiderSavingsHistoryView memory savings = _savings();
        assertEq(savings.riderAddress, RIDER);
        assertEq(savings.totalAmountSaved, 2 * USDC_UNIT);
        assertEq(savings.entries, 1);

        HRiderSavings memory entry = getInvestmentStorage(INVESTMENT_ID).riderSavings.savings[0];
        assertEq(entry.riderAddress, RIDER);
        assertEq(entry.amountSaved, 2 * USDC_UNIT);
        assertEq(entry.timeSaved, block.timestamp);

        assertEq(stats.riderSavingsHeldUsd, 2 * USDC_UNIT);
    }

    function test_RecordRiderSavings_AccumulatesAcrossPayments() public {
        _record(2 * USDC_UNIT);
        _record(2 * USDC_UNIT);
        _record(3 * USDC_UNIT);

        HRiderSavingsHistoryView memory savings = _savings();
        assertEq(savings.totalAmountSaved, 7 * USDC_UNIT);
        assertEq(savings.entries, 3);
        assertEq(stats.riderSavingsHeldUsd, 7 * USDC_UNIT);

        HRiderSavings memory lastEntry = getInvestmentStorage(INVESTMENT_ID).riderSavings.savings[2];
        assertEq(lastEntry.amountSaved, 3 * USDC_UNIT);
    }

    /// @dev The savings record always attributes to the hired rider on the investment.
    function test_RecordRiderSavings_AttributesToHiredRider() public {
        address newRider = address(0xCAFE);
        getInvestmentStorage(INVESTMENT_ID).riderWhoHiredIt = newRider;

        _record(1 * USDC_UNIT);

        assertEq(_savings().riderAddress, newRider);
        assertEq(getInvestmentStorage(INVESTMENT_ID).riderSavings.savings[0].riderAddress, newRider);
    }

    //<editor-fold desc="Helpers">

    struct HRiderSavingsHistoryView {
        address riderAddress;
        uint256 totalAmountSaved;
        uint256 entries;
    }

    function _savings() internal view returns (HRiderSavingsHistoryView memory view_) {
        HRiderSavingsHistory storage savings = getInvestmentStorage(INVESTMENT_ID).riderSavings;
        view_.riderAddress = savings.riderAddress;
        view_.totalAmountSaved = savings.totalAmountSaved;
        view_.entries = savings.savings.length;
    }

    //</editor-fold desc="Helpers">
}
