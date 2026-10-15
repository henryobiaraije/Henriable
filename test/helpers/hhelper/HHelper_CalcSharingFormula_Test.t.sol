// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HAsset, HInvestment, HSharingBreakdown, USDC_UNIT} from "../../../src/types/common.sol";
import {HHelper} from "../../../src/helpers/HHelper.sol";
import {HenriableVehicleNFT} from "../../../src/HenriableVehicleNFT.sol";

/// @title Tests for {HHelper.calcSharingFormula}.
/// @notice The split is target-driven, not percentage-driven: each payment first fills the
///         senior pool up to its remaining target, then the junior pool up to its target, and
///         the owner receives whatever is left. The rider's refundable savings charge is
///         excluded from the split. The asset used here needs 5 senior seats at (100 + 5) = 525
///         and 20 junior seats at (25 + 5) = 600, with an owner target of 75. Every USD amount is
///         in USDC base units (6 decimals), written as `<dollars> * USDC_UNIT`.
contract HHelperCalcSharingFormulaTest is Test, HHelper {
    bytes32 internal constant ASSET_ID = bytes32("keke-0001");
    bytes32 internal constant INVESTMENT_ID = bytes32("inv-0001");
    address internal constant SENIOR_INVESTOR = address(0x5111);
    address internal constant JUNIOR_INVESTOR = address(0x7111);

    uint256 internal constant SENIOR_POOL_TARGET = 525 * USDC_UNIT;
    uint256 internal constant JUNIOR_POOL_TARGET = 600 * USDC_UNIT;

    constructor() HHelper(address(this), IERC20(address(0)), new HenriableVehicleNFT(address(this))) {}

    function setUp() public {
        seedAsset();
        seedInvestment();
    }

    function seedAsset() internal {
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

        assetsList.push(asset);
        assets[ASSET_ID] = assetsList.length;
    }

    function seedInvestment() internal {
        HInvestment storage investment = investmentsList.push();
        investment.investmentId = INVESTMENT_ID;
        investment.assetId = ASSET_ID;
        investment.minimumRiderPeriodicPayingsUsd = 100 * USDC_UNIT;
        investment.seniorInvestorsList.push(SENIOR_INVESTOR);
        investment.seniorInvestors[SENIOR_INVESTOR] = investment.seniorInvestorsList.length;
        investment.juniorInvestorsList.push(JUNIOR_INVESTOR);
        investment.juniorInvestors[JUNIOR_INVESTOR] = investment.juniorInvestorsList.length;
        investments[INVESTMENT_ID] = investmentsList.length;
    }

    function setSeniorPaidSoFar(uint256 amount) internal {
        getInvestmentStorage(INVESTMENT_ID).investorPayoutHistory[SENIOR_INVESTOR].totalAmountPaid = amount;
    }

    function setJuniorPaidSoFar(uint256 amount) internal {
        getInvestmentStorage(INVESTMENT_ID).investorPayoutHistory[JUNIOR_INVESTOR].totalAmountPaid = amount;
    }

    function split(uint256 amount) internal view returns (HSharingBreakdown memory) {
        return calcSharingFormula(getInvestmentStorage(INVESTMENT_ID), getAssetStorage(ASSET_ID), amount);
    }

    //<editor-fold desc="Senior paid first">

    function test_CalcSharingFormula_PaysSeniorFirst_WhenSeniorStillOwed() public {
        HSharingBreakdown memory breakdown = split(100 * USDC_UNIT);

        assertEq(breakdown.seniorInvestorsAmount, 100 * USDC_UNIT);
        assertEq(breakdown.juniorInvestorsAmount, 0);
        assertEq(breakdown.ownerAmount, 0);
    }

    function test_CalcSharingFormula_PaysOnlySenior_WhenAmountBelowRemaining() public {
        HSharingBreakdown memory breakdown = split(1);

        assertEq(breakdown.seniorInvestorsAmount, 1);
        assertEq(breakdown.juniorInvestorsAmount, 0);
        assertEq(breakdown.ownerAmount, 0);
    }

    /// @notice The senior share never exceeds what the pool is still owed; the remainder spills
    ///         to the junior pool.
    function test_CalcSharingFormula_CapsSeniorAtRemaining_ThenFillsJunior() public {
        setSeniorPaidSoFar(SENIOR_POOL_TARGET - 25 * USDC_UNIT);

        HSharingBreakdown memory breakdown = split(100 * USDC_UNIT);

        assertEq(breakdown.seniorInvestorsAmount, 25 * USDC_UNIT);
        assertEq(breakdown.juniorInvestorsAmount, 75 * USDC_UNIT);
        assertEq(breakdown.ownerAmount, 0);
    }

    //</editor-fold desc="Senior paid first">

    //<editor-fold desc="Junior second">

    function test_CalcSharingFormula_PaysJunior_WhenSeniorFullyPaid() public {
        setSeniorPaidSoFar(SENIOR_POOL_TARGET);

        HSharingBreakdown memory breakdown = split(100 * USDC_UNIT);

        assertEq(breakdown.seniorInvestorsAmount, 0);
        assertEq(breakdown.juniorInvestorsAmount, 100 * USDC_UNIT);
        assertEq(breakdown.ownerAmount, 0);
    }

    function test_CalcSharingFormula_CapsJuniorAtRemaining_ThenPaysOwner() public {
        setSeniorPaidSoFar(SENIOR_POOL_TARGET);
        setJuniorPaidSoFar(JUNIOR_POOL_TARGET - 50 * USDC_UNIT);

        HSharingBreakdown memory breakdown = split(100 * USDC_UNIT);

        assertEq(breakdown.seniorInvestorsAmount, 0);
        assertEq(breakdown.juniorInvestorsAmount, 50 * USDC_UNIT);
        assertEq(breakdown.ownerAmount, 50 * USDC_UNIT);
    }

    //</editor-fold desc="Junior second">

    //<editor-fold desc="Owner last">

    function test_CalcSharingFormula_PaysOwner_WhenBothPoolsFullyPaid() public {
        setSeniorPaidSoFar(SENIOR_POOL_TARGET);
        setJuniorPaidSoFar(JUNIOR_POOL_TARGET);

        HSharingBreakdown memory breakdown = split(100 * USDC_UNIT);

        assertEq(breakdown.seniorInvestorsAmount, 0);
        assertEq(breakdown.juniorInvestorsAmount, 0);
        assertEq(breakdown.ownerAmount, 100 * USDC_UNIT);
    }

    function test_CalcSharingFormula_PaysOwner_WhenBothPoolsOverpaid() public {
        setSeniorPaidSoFar(SENIOR_POOL_TARGET + 100 * USDC_UNIT);
        setJuniorPaidSoFar(JUNIOR_POOL_TARGET + 100 * USDC_UNIT);

        HSharingBreakdown memory breakdown = split(100 * USDC_UNIT);

        assertEq(breakdown.ownerAmount, 100 * USDC_UNIT);
    }

    //</editor-fold desc="Owner last">

    /// @notice A micro-USDC payment is split in base units: while senior is owed it all goes to
    ///         senior, with nothing lost to rounding.
    function test_CalcSharingFormula_SplitsMicroPayment_InBaseUnits() public {
        HSharingBreakdown memory breakdown = split(140_000);

        assertEq(breakdown.seniorInvestorsAmount, 140_000);
        assertEq(breakdown.juniorInvestorsAmount, 0);
        assertEq(breakdown.ownerAmount, 0);
    }
}
