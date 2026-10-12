// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HAsset, HInvestment} from "../../../src/types/common.sol";
import {HHelper} from "../../../src/helpers/HHelper.sol";

/// @title Tests for {HHelper.calcSeniorPoolPaidSoFar}.
/// @notice The helper sums the payout history of every senior investor on an investment.
contract HHelperCalcSeniorPoolPaidSoFarTest is Test, HHelper {
    bytes32 internal constant ASSET_ID = bytes32("keke-0001");
    bytes32 internal constant INVESTMENT_ID = bytes32("inv-0001");
    address internal constant SENIOR_ONE = address(0x5111);
    address internal constant SENIOR_TWO = address(0x5222);

    constructor() HHelper(address(this), IERC20(address(0))) {}

    function seedInvestment() internal {
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
            totalNumberOfSeniorInvestorsNeeded: 2,
            totalNumberOfJuniorInvestorsNeeded: 20
        });
        assetsList.push(asset);
        assets[ASSET_ID] = assetsList.length;

        HInvestment storage investment = investmentsList.push();
        investment.investmentId = INVESTMENT_ID;
        investment.assetId = ASSET_ID;
        investments[INVESTMENT_ID] = investmentsList.length;
    }

    /// @dev Mirrors {Henriable.actionInvest}: every seat pushes the investor and records
    ///      its 1-based position in the index mapping.
    function addSeniorSeat(HInvestment storage investment, address investor) internal {
        investment.seniorInvestorsList.push(investor);
        investment.seniorInvestors[investor] = investment.seniorInvestorsList.length;
    }

    function test_CalcSeniorPoolPaidSoFar_ReturnsZero_WhenNoSeniorInvestors() public {
        seedInvestment();

        uint256 paidSoFar = calcSeniorPoolPaidSoFar(getInvestmentStorage(INVESTMENT_ID));

        assertEq(paidSoFar, 0);
    }

    function test_CalcSeniorPoolPaidSoFar_SumsEverySeniorInvestorPayout() public {
        seedInvestment();

        HInvestment storage investment = getInvestmentStorage(INVESTMENT_ID);
        addSeniorSeat(investment, SENIOR_ONE);
        addSeniorSeat(investment, SENIOR_TWO);
        investment.investorPayoutHistory[SENIOR_ONE].totalAmountPaid = 100;
        investment.investorPayoutHistory[SENIOR_TWO].totalAmountPaid = 250;

        uint256 paidSoFar = calcSeniorPoolPaidSoFar(investment);

        assertEq(paidSoFar, 350);
    }

    function test_CalcSeniorPoolPaidSoFar_CountsInvestorOnce_WhenHoldingMultipleSeats() public {
        seedInvestment();

        HInvestment storage investment = getInvestmentStorage(INVESTMENT_ID);
        addSeniorSeat(investment, SENIOR_ONE);
        addSeniorSeat(investment, SENIOR_ONE);
        addSeniorSeat(investment, SENIOR_TWO);
        investment.investorPayoutHistory[SENIOR_ONE].totalAmountPaid = 200;
        investment.investorPayoutHistory[SENIOR_TWO].totalAmountPaid = 100;

        uint256 paidSoFar = calcSeniorPoolPaidSoFar(investment);

        assertEq(paidSoFar, 300);
    }
}
