// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HAsset, HInvestment} from "../../../src/types/common.sol";
import {HHelper} from "../../../src/helpers/HHelper.sol";

/// @title Tests for {HHelper.getRiderAmountToPayNow}.
/// @notice The getter reports the next instalment the calling rider owes: the periodic
///         minimum (capped by the outstanding balance on the final instalment) plus the
///         asset's per-period savings charge. It is 0 for non-riders and once the target
///         total has been paid.
contract HHelperGetRiderAmountToPayNowTest is Test, HHelper {
    bytes32 internal constant ASSET_ID = bytes32("keke-0001");
    bytes32 internal constant INVESTMENT_ID = bytes32("inv-0001");
    address internal constant RIDER = address(0xB0B);
    uint256 internal constant MINIMUM_PAYMENT = 100;
    uint256 internal constant SAVINGS_CHARGE = 2;

    constructor() HHelper(address(this), IERC20(address(0))) {}

    function setUp() public {
        HAsset memory asset = HAsset({
            id: ASSET_ID,
            active: true,
            name: bytes32("Keke"),
            costPrice: 1_000,
            sellPrice: 1_200,
            oneSeniorInvestorBuyingPrice: 100,
            oneSeniorInvestorProfit: 5,
            oneJuniorInvestorBuyingPrice: 25,
            oneJuniorInvestorProfit: 5,
            riderSlashableRepayableExtraCharge: SAVINGS_CHARGE,
            ownerProfit: 75,
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

    function test_GetRiderAmountToPayNow_ReturnsMinimumPlusSavings_WhenFullBalanceOutstanding() public {
        vm.prank(RIDER);
        uint256 amount = this.getRiderAmountToPayNow(INVESTMENT_ID);

        assertEq(amount, MINIMUM_PAYMENT + SAVINGS_CHARGE);
    }

    function test_GetRiderAmountToPayNow_ReturnsRemainingPlusSavings_WhenBelowMinimum() public {
        getInvestmentStorage(INVESTMENT_ID).riderPayinsHistory.totalAmountPaid = 1_150;

        vm.prank(RIDER);
        uint256 amount = this.getRiderAmountToPayNow(INVESTMENT_ID);

        assertEq(amount, 50 + SAVINGS_CHARGE);
    }

    function test_GetRiderAmountToPayNow_ReturnsZero_WhenPaymentsCompleted() public {
        getInvestmentStorage(INVESTMENT_ID).riderPayinsHistory.totalAmountPaid = 1_200;

        vm.prank(RIDER);
        uint256 amount = this.getRiderAmountToPayNow(INVESTMENT_ID);

        assertEq(amount, 0);
    }

    function test_GetRiderAmountToPayNow_ReturnsZero_WhenCallerIsNotTheHiredRider() public {
        vm.prank(address(0xDEAD));
        uint256 amount = this.getRiderAmountToPayNow(INVESTMENT_ID);

        assertEq(amount, 0);
    }

    function test_GetRiderAmountToPayNow_Reverts_WhenInvestmentDoesNotExist() public {
        vm.prank(RIDER);
        vm.expectRevert();
        this.getRiderAmountToPayNow(bytes32("missing"));
    }
}
