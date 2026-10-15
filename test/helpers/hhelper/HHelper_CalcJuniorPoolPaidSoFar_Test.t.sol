// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HAsset, HInvestment, USDC_UNIT} from "../../../src/types/common.sol";
import {HHelper} from "../../../src/helpers/HHelper.sol";
import {HenriableVehicleNFT} from "../../../src/HenriableVehicleNFT.sol";

/// @title Tests for {HHelper.calcJuniorPoolPaidSoFar}.
/// @notice The helper sums the payout history of every junior investor on an investment.
///         Payout amounts are in USDC base units (6 decimals).
contract HHelperCalcJuniorPoolPaidSoFarTest is Test, HHelper {
    bytes32 internal constant ASSET_ID = bytes32("keke-0001");
    bytes32 internal constant INVESTMENT_ID = bytes32("inv-0001");
    address internal constant JUNIOR_ONE = address(0x7111);
    address internal constant JUNIOR_TWO = address(0x7222);

    constructor() HHelper(address(this), IERC20(address(0)), new HenriableVehicleNFT(address(this))) {}

    function seedInvestment() internal {
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
            totalNumberOfSeniorInvestorsNeeded: 2,
            totalNumberOfJuniorInvestorsNeeded: 2
        });
        assetsList.push(asset);
        assets[ASSET_ID] = assetsList.length;

        HInvestment storage investment = investmentsList.push();
        investment.investmentId = INVESTMENT_ID;
        investment.assetId = ASSET_ID;
        investments[INVESTMENT_ID] = investmentsList.length;
    }

    /// @dev Mirrors {Henriable.actionInvest}: every seat pushes the investor and records its
    ///      1-based position in the index mapping.
    function addJuniorSeat(HInvestment storage investment, address investor) internal {
        investment.juniorInvestorsList.push(investor);
        investment.juniorInvestors[investor] = investment.juniorInvestorsList.length;
    }

    function test_CalcJuniorPoolPaidSoFar_ReturnsZero_WhenNoJuniorInvestors() public {
        seedInvestment();

        uint256 paidSoFar = calcJuniorPoolPaidSoFar(getInvestmentStorage(INVESTMENT_ID));

        assertEq(paidSoFar, 0);
    }

    function test_CalcJuniorPoolPaidSoFar_SumsEveryJuniorInvestorPayout() public {
        seedInvestment();

        HInvestment storage investment = getInvestmentStorage(INVESTMENT_ID);
        addJuniorSeat(investment, JUNIOR_ONE);
        addJuniorSeat(investment, JUNIOR_TWO);
        investment.investorPayoutHistory[JUNIOR_ONE].totalAmountPaid = 100 * USDC_UNIT;
        investment.investorPayoutHistory[JUNIOR_TWO].totalAmountPaid = 250 * USDC_UNIT;

        uint256 paidSoFar = calcJuniorPoolPaidSoFar(investment);

        assertEq(paidSoFar, 350 * USDC_UNIT);
    }

    function test_CalcJuniorPoolPaidSoFar_CountsInvestorOnce_WhenHoldingMultipleSeats() public {
        seedInvestment();

        HInvestment storage investment = getInvestmentStorage(INVESTMENT_ID);
        addJuniorSeat(investment, JUNIOR_ONE);
        addJuniorSeat(investment, JUNIOR_ONE);
        addJuniorSeat(investment, JUNIOR_TWO);
        investment.investorPayoutHistory[JUNIOR_ONE].totalAmountPaid = 200 * USDC_UNIT;
        investment.investorPayoutHistory[JUNIOR_TWO].totalAmountPaid = 100 * USDC_UNIT;

        uint256 paidSoFar = calcJuniorPoolPaidSoFar(investment);

        assertEq(paidSoFar, 300 * USDC_UNIT);
    }
}
