// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HAsset, HInvestment, USDC_UNIT} from "../../../src/types/common.sol";
import {HHelper} from "../../../src/helpers/HHelper.sol";

/// @title Tests for {HHelper.getRiderAmountToPayNow}.
/// @notice The getter reports the next instalment the calling rider owes: the periodic
///         minimum (capped by the outstanding balance on the final instalment) plus the
///         asset's per-period savings charge. It is 0 for non-riders and once the target
///         total has been paid. Every USD amount is in USDC base units (6 decimals).
contract HHelperGetRiderAmountToPayNowTest is Test, HHelper {
    bytes32 internal constant ASSET_ID = bytes32("keke-0001");
    bytes32 internal constant INVESTMENT_ID = bytes32("inv-0001");
    address internal constant RIDER = address(0xB0B);
    uint256 internal constant MINIMUM_PAYMENT = 100 * USDC_UNIT;
    uint256 internal constant SAVINGS_CHARGE = 2 * USDC_UNIT;

    constructor() HHelper(address(this), IERC20(address(0))) {}

    function setUp() public {
        HAsset memory asset = HAsset({
            id: ASSET_ID,
            active: true,
            name: bytes32("Keke"),
            costPrice: 1_000 * USDC_UNIT,
            sellPrice: 1_200 * USDC_UNIT,
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

    function test_GetRiderAmountToPayNow_ReturnsMinimumPlusSavings_WhenFullBalanceOutstanding() public {
        vm.prank(RIDER);
        uint256 amount = this.getRiderAmountToPayNow(INVESTMENT_ID);

        assertEq(amount, MINIMUM_PAYMENT + SAVINGS_CHARGE);
    }

    function test_GetRiderAmountToPayNow_ReturnsRemainingPlusSavings_WhenBelowMinimum() public {
        getInvestmentStorage(INVESTMENT_ID).riderPayinsHistory.totalAmountPaid = 1_150 * USDC_UNIT;

        vm.prank(RIDER);
        uint256 amount = this.getRiderAmountToPayNow(INVESTMENT_ID);

        assertEq(amount, 50 * USDC_UNIT + SAVINGS_CHARGE);
    }

    function test_GetRiderAmountToPayNow_ReturnsZero_WhenPaymentsCompleted() public {
        getInvestmentStorage(INVESTMENT_ID).riderPayinsHistory.totalAmountPaid = 1_200 * USDC_UNIT;

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

    /// @notice Reproduces the reported case with micro-USDC amounts: a $0.6594 periodic
    ///         minimum plus the $0.14 savings charge yields $0.7994 (~$0.80), so the bare
    ///         $0.66 minimum is deliberately not what the rider transfers.
    function test_GetRiderAmountToPayNow_AddsSavingsCharge_ToMicroMinimum() public {
        bytes32 microAssetId = bytes32("keke-micro");
        HAsset memory microAsset = getAssetStorage(ASSET_ID);
        microAsset.id = microAssetId;
        microAsset.name = bytes32("Keke-Micro");
        microAsset.riderSlashableRepayableExtraCharge = 140_000;
        assetsList.push(microAsset);
        assets[microAssetId] = assetsList.length;

        bytes32 microInvestmentId = bytes32("inv-micro");
        HInvestment storage microInvestment = investmentsList.push();
        microInvestment.investmentId = microInvestmentId;
        microInvestment.assetId = microAssetId;
        microInvestment.minimumRiderPeriodicPayingsUsd = 659_400;
        microInvestment.riderWhoHiredIt = RIDER;
        investments[microInvestmentId] = investmentsList.length;

        vm.prank(RIDER);
        uint256 amount = this.getRiderAmountToPayNow(microInvestmentId);

        assertEq(amount, 659_400 + 140_000);
    }
}
