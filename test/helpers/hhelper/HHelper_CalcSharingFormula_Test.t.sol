// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HAsset, HInvestment, HSharingBreakdown} from "../../../src/types/common.sol";
import {HHelper} from "../../../src/helpers/HHelper.sol";

/// @title Tests for {HHelper.calcSharingFormula}.
/// @notice The formula excludes the rider's refundable savings charge. While the senior pool is
///         being paid off, each payment is 70% to senior, 25% to junior and the rest to the
///         owner, with the senior share capped at what it is still owed. Once the senior pool
///         is fully paid, the split becomes 60% to junior and 40% to the owner. The worked
///         example uses a senior target of 5 x (100 + 5) = 525.
contract HHelperCalcSharingFormulaTest is Test, HHelper {
    bytes32 internal constant ASSET_ID = bytes32("keke-0001");
    bytes32 internal constant INVESTMENT_ID = bytes32("inv-0001");
    address internal constant SENIOR_INVESTOR = address(0x5111);
    uint256 internal constant SENIOR_POOL_TARGET = 525;

    constructor() HHelper(address(this), IERC20(address(0))) {}

    function setUp() public {
        seedAsset();
        seedInvestment();
    }

    function seedAsset() internal {
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

        assetsList.push(asset);
        assets[ASSET_ID] = assetsList.length;
    }

    function seedInvestment() internal {
        HInvestment storage investment = investmentsList.push();
        investment.investmentId = INVESTMENT_ID;
        investment.assetId = ASSET_ID;
        investment.minimumRiderPeriodicPayingsUsd = 100;
        investment.seniorInvestorsList.push(SENIOR_INVESTOR);
        investment.seniorInvestors[SENIOR_INVESTOR] = investment.seniorInvestorsList.length;
        investments[INVESTMENT_ID] = investmentsList.length;
    }

    function setSeniorPaidSoFar(uint256 amount) internal {
        getInvestmentStorage(INVESTMENT_ID).investorPayoutHistory[SENIOR_INVESTOR].totalAmountPaid = amount;
    }

    function split(uint256 amount) internal view returns (HSharingBreakdown memory) {
        return calcSharingFormula(getInvestmentStorage(INVESTMENT_ID), getAssetStorage(ASSET_ID), amount);
    }

    function test_CalcSharingFormula_SplitsSeniorJuniorOwner_WhenSeniorStillOwed() public {
        HSharingBreakdown memory breakdown = split(100);

        assertEq(breakdown.seniorInvestorsAmount, 70);
        assertEq(breakdown.juniorInvestorsAmount, 25);
        assertEq(breakdown.ownerAmount, 5);
    }

    function test_CalcSharingFormula_CapsSeniorAtRemaining_WhenSeniorAlmostPaid() public {
        setSeniorPaidSoFar(500);

        HSharingBreakdown memory breakdown = split(100);

        assertEq(breakdown.seniorInvestorsAmount, 25);
        assertEq(breakdown.juniorInvestorsAmount, 25);
        assertEq(breakdown.ownerAmount, 50);
    }

    function test_CalcSharingFormula_SplitsJuniorAndOwner_WhenSeniorFullyPaid() public {
        setSeniorPaidSoFar(SENIOR_POOL_TARGET);

        HSharingBreakdown memory breakdown = split(100);

        assertEq(breakdown.seniorInvestorsAmount, 0);
        assertEq(breakdown.juniorInvestorsAmount, 60);
        assertEq(breakdown.ownerAmount, 40);
    }

    function test_CalcSharingFormula_SplitsJuniorAndOwner_WhenSeniorOverpaid() public {
        setSeniorPaidSoFar(SENIOR_POOL_TARGET + 100);

        HSharingBreakdown memory breakdown = split(100);

        assertEq(breakdown.seniorInvestorsAmount, 0);
        assertEq(breakdown.juniorInvestorsAmount, 60);
        assertEq(breakdown.ownerAmount, 40);
    }

    function test_CalcSharingFormula_OwnerAbsorbsRoundingDust() public {
        HSharingBreakdown memory breakdown = split(101);

        assertEq(breakdown.seniorInvestorsAmount, 70);
        assertEq(breakdown.juniorInvestorsAmount, 25);
        assertEq(breakdown.ownerAmount, 6);
    }
}
