// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    HAsset,
    HInvestmentStatus,
    HInvestmentType,
    HInvestor,
    HRider,
    USDC_UNIT
} from "../../src/types/common.sol";
import {Henriable} from "../../src/Henriable.sol";
import {HenriableVehicleNFT} from "../../src/HenriableVehicleNFT.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";

/// @title End-to-end happy-path test of the whole Henriable process.
/// @notice One journey from scratch: register an asset, open an investment, have four investors
///         fund it, have three riders apply to hire it (two are refunded), have the accepted
///         rider pay every instalment on schedule (including an omitted payment that the admin
///         covers by extending the deadline and slashing savings), and finish with the rider
///         owning the asset, their savings refunded, and every investor and the owner paid in
///         full. Only the happy path is exercised; every amount is in USDC base units (6
///         decimals) and `USDC_UNIT` is one whole USDC.
///
/// @dev    Schedule. The asset needs two senior and two junior slots and is priced so the rider's
///         sell price exactly covers every promised payout:
///         - senior slot: buying 45 + profit 5  => 50 per investor, pool target 100
///         - junior slot: buying 25 + profit 5  => 30 per investor, pool target  60
///         - costPrice 140, ownerProfit 60, sellPrice 220, savings charge 2
///         The investment charges a 40 USDC periodic minimum over 1-day periods and a 50 USDC
///         initial buy-in. The buy-in is credited toward the 220 USDC hire-purchase total and
///         shared at accept (50 to the senior pool, which is owed first), leaving 170 USDC paid
///         as four 40 USDC instalments and one final 10 USDC instalment. Payouts are
///         target-driven: senior is filled to 100, then junior to 60, then the owner receives the
///         rest (60, plus the 4 USDC slashed savings, so 64).
contract HenriableWholeProcessTest is Test {
    bytes32 internal constant ASSET_ID = bytes32("keke-whole");
    bytes32 internal constant INVESTMENT_ID = bytes32("inv-whole");

    address internal constant SENIOR_ONE = address(0x5101);
    address internal constant SENIOR_TWO = address(0x5102);
    address internal constant JUNIOR_ONE = address(0x7101);
    address internal constant JUNIOR_TWO = address(0x7102);
    address internal constant RIDER_ACCEPTED = address(0xB101);
    address internal constant RIDER_REJECTED_ONE = address(0xB102);
    address internal constant RIDER_REJECTED_TWO = address(0xB103);

    uint256 internal constant SENIOR_BUYING = 45 * USDC_UNIT;
    uint256 internal constant SENIOR_PROFIT = 5 * USDC_UNIT;
    uint256 internal constant JUNIOR_BUYING = 25 * USDC_UNIT;
    uint256 internal constant JUNIOR_PROFIT = 5 * USDC_UNIT;
    uint256 internal constant COST_PRICE = 140 * USDC_UNIT;
    uint256 internal constant SELL_PRICE = 220 * USDC_UNIT;
    uint256 internal constant OWNER_PROFIT = 60 * USDC_UNIT;
    uint256 internal constant SAVINGS_CHARGE = 2 * USDC_UNIT;
    uint256 internal constant MINIMUM_PAYMENT = 40 * USDC_UNIT;
    uint256 internal constant INITIAL_BUYIN = 50 * USDC_UNIT;
    uint256 internal constant PERIOD = 1 days;
    uint256 internal constant PERIODIC_MINUTES = 1440;

    uint256 internal constant SENIOR_PER_INVESTOR_TARGET = SENIOR_BUYING + SENIOR_PROFIT;
    uint256 internal constant JUNIOR_PER_INVESTOR_TARGET = JUNIOR_BUYING + JUNIOR_PROFIT;

    Henriable internal henriable;
    HenriableVehicleNFT internal vehicleNft;
    MockUSDC internal usdc;

    function test_WholeProcess_HappyPath_FromAssetToOwnershipTransfer() public {
        //<editor-fold desc="1. Deploy and register the asset and investment">

        usdc = new MockUSDC();
        vehicleNft = new HenriableVehicleNFT(address(this));
        henriable = new Henriable(address(this), IERC20(address(usdc)), vehicleNft);
        vehicleNft.setMinter(address(henriable));

        henriable.actionAdminAddAsset(_asset());
        henriable.actionAdminAddInvestment(INVESTMENT_ID, ASSET_ID, INITIAL_BUYIN, PERIODIC_MINUTES, MINIMUM_PAYMENT);

        //</editor-fold desc="1. Deploy and register the asset and investment">

        //<editor-fold desc="2. Four investors fund the investment">

        uint256 investmentStart = block.timestamp + 10;
        henriable.actionAdminSetNextInvestmentTimes(INVESTMENT_ID, investmentStart, investmentStart + 1 days);
        vm.warp(investmentStart + 1);

        _invest(SENIOR_ONE, HInvestmentType.Senior, SENIOR_BUYING);
        _invest(SENIOR_TWO, HInvestmentType.Senior, SENIOR_BUYING);
        _invest(JUNIOR_ONE, HInvestmentType.Junior, JUNIOR_BUYING);
        _invest(JUNIOR_TWO, HInvestmentType.Junior, JUNIOR_BUYING);

        assertEq(uint256(_status()), uint256(HInvestmentStatus.InvestmentDone));

        // Funding completion mints the vehicle title to the platform.
        (, , uint256 nftTokenId, , ) = henriable.getInvestmentRiderInfo(0);
        assertEq(nftTokenId, 1);
        assertEq(vehicleNft.ownerOf(nftTokenId), address(henriable));
        assertEq(vehicleNft.getMinter(), address(henriable));
        assertEq(address(henriable.getVehicleNft()), address(vehicleNft));

        //</editor-fold desc="2. Four investors fund the investment">

        //<editor-fold desc="3. Open the hire round and register three riders">

        uint256 hireStart = block.timestamp + 10;
        henriable.actionSetNextHireRoundTime(INVESTMENT_ID, hireStart, hireStart + 1 days);
        vm.warp(hireStart + 1);

        uint256 journeyStart = block.timestamp;

        _registerRider(RIDER_ACCEPTED);
        _registerRider(RIDER_REJECTED_ONE);
        _registerRider(RIDER_REJECTED_TWO);

        assertEq(henriable.getHireRequestsCount(), 3);

        //</editor-fold desc="3. Open the hire round and register three riders">

        //<editor-fold desc="4. Accept one rider; the other two are refunded">

        uint256 refundedBeforeOne = usdc.balanceOf(RIDER_REJECTED_ONE);
        uint256 refundedBeforeTwo = usdc.balanceOf(RIDER_REJECTED_TWO);

        henriable.actionAdminAcceptRider(INVESTMENT_ID, RIDER_ACCEPTED);

        assertEq(uint256(_status()), uint256(HInvestmentStatus.Hired));
        (address hiredRider, , , , ) = henriable.getInvestmentRiderInfo(0);
        assertEq(hiredRider, RIDER_ACCEPTED);
        assertEq(_nextPayinDate(), journeyStart + PERIOD);

        // The two rejected applicants get their initial buy-in back and are marked rejected.
        assertEq(usdc.balanceOf(RIDER_REJECTED_ONE) - refundedBeforeOne, INITIAL_BUYIN);
        assertEq(usdc.balanceOf(RIDER_REJECTED_TWO) - refundedBeforeTwo, INITIAL_BUYIN);
        assertEq(henriable.getRejectedRiderIndex(bytes32(uint256(uint160(RIDER_REJECTED_ONE))), INVESTMENT_ID), 1);
        assertEq(henriable.getRejectedRiderIndex(bytes32(uint256(uint160(RIDER_REJECTED_TWO))), INVESTMENT_ID), 1);

        // The accepted rider's 50 USDC buy-in is credited toward their total and shared at once:
        // senior is owed first, so the senior pool receives all 50 (25 per senior investor).
        assertEq(henriable.getInvestmentRiderPayinsHistory(0).totalAmountPaid, INITIAL_BUYIN);
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, SENIOR_ONE).totalAmountPaid, 25 * USDC_UNIT);
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, SENIOR_TWO).totalAmountPaid, 25 * USDC_UNIT);

        HRider memory acceptedProfile = henriable.getRider(RIDER_ACCEPTED);
        assertEq(acceptedProfile.riderAddress, RIDER_ACCEPTED);

        //</editor-fold desc="4. Accept one rider; the other two are refunded">

        //<editor-fold desc="5. Two instalments finish the senior pool and start the junior pool">

        _payInstalment(MINIMUM_PAYMENT, journeyStart + 2 * PERIOD);
        _payInstalment(MINIMUM_PAYMENT, journeyStart + 3 * PERIOD);

        assertEq(henriable.getInvestmentRiderPayinsHistory(0).totalAmountPaid, INITIAL_BUYIN + 2 * MINIMUM_PAYMENT);
        assertEq(henriable.getInvestmentRiderSavings(0).totalAmountSaved, 2 * SAVINGS_CHARGE);

        // Senior is now fully paid (50 + 10 + 40 = 100), junior has started (30).
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, SENIOR_ONE).totalAmountPaid, SENIOR_PER_INVESTOR_TARGET);
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, SENIOR_TWO).totalAmountPaid, SENIOR_PER_INVESTOR_TARGET);
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, JUNIOR_ONE).totalAmountPaid, 15 * USDC_UNIT);

        //</editor-fold desc="5. Two instalments finish the senior pool and start the junior pool">

        //<editor-fold desc="6. The rider omits the next payment: admin extends and slashes savings">

        // Warp past the due date so the payment is genuinely late, then grant more time and slash
        // the rider's 4 USDC of savings as a penalty. Senior is fully paid, so the slash goes to
        // the junior pool (2 per junior investor).
        vm.warp(journeyStart + 3 * PERIOD + 1);
        henriable.actionAdminExtendRiderPayingForInvestment(INVESTMENT_ID, journeyStart + 5 * PERIOD, 4 * USDC_UNIT);

        assertEq(_nextPayinDate(), journeyStart + 5 * PERIOD);
        assertEq(henriable.getInvestmentRiderSavings(0).totalAmountSaved, 0);
        assertEq(henriable.getStats().totalRiderSavingsSlashedUsd, 4 * USDC_UNIT);
        assertEq(henriable.getRiderSavingsSlashesCount(), 1);
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, JUNIOR_ONE).totalAmountPaid, 17 * USDC_UNIT);

        //</editor-fold desc="6. The rider omits the next payment: admin extends and slashes savings">

        //<editor-fold desc="7. The rider keeps paying until the debt is cleared">

        _payInstalment(MINIMUM_PAYMENT, journeyStart + 6 * PERIOD);
        _payInstalment(MINIMUM_PAYMENT, journeyStart + 7 * PERIOD);

        // Junior is now fully paid (15 + 2 slash + 13 + ... = 30 each).
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, JUNIOR_ONE).totalAmountPaid, JUNIOR_PER_INVESTOR_TARGET);
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, JUNIOR_TWO).totalAmountPaid, JUNIOR_PER_INVESTOR_TARGET);

        // Final instalment: the 10 USDC outstanding balance plus the 2 USDC savings charge.
        uint256 riderBalanceBeforeFinal = usdc.balanceOf(RIDER_ACCEPTED);
        _payInstalment(SELL_PRICE - INITIAL_BUYIN - 4 * MINIMUM_PAYMENT, journeyStart + 8 * PERIOD);

        // The rider pays 12 USDC but gets the 6 USDC of accumulated savings back, so the net cost
        // is 6 USDC.
        assertEq(riderBalanceBeforeFinal - usdc.balanceOf(RIDER_ACCEPTED), 6 * USDC_UNIT);

        //</editor-fold desc="7. The rider keeps paying until the debt is cleared">

        //<editor-fold desc="8. Completion: ownership, savings and history">

        assertEq(uint256(_status()), uint256(HInvestmentStatus.Complete));
        assertEq(henriable.getInvestmentRiderPayinsHistory(0).totalAmountPaid, SELL_PRICE);
        assertEq(henriable.getInvestmentRiderPayinsHistory(0).totalNumberOfTimesPaid, 5);

        // Savings are refunded in full and cleared.
        assertEq(henriable.getInvestmentRiderSavings(0).totalAmountSaved, 0);
        assertEq(henriable.getStats().riderSavingsHeldUsd, 0);

        // The completion lists and times are recorded.
        assertEq(_nextPayinDate(), journeyStart + 8 * PERIOD);
        (, , , uint256 completedAt, uint256 transferredAt) = henriable.getInvestmentRiderInfo(0);
        assertEq(completedAt, block.timestamp);
        assertEq(transferredAt, block.timestamp);
        assertEq(henriable.getCompletedRiderInvestmentsCount(), 1);
        assertEq(henriable.getInvestmentsCompletedCount(), 1);

        // The vehicle title is handed to the rider on completion.
        assertEq(vehicleNft.ownerOf(nftTokenId), RIDER_ACCEPTED);

        //</editor-fold desc="8. Completion: ownership, savings and history">

        //<editor-fold desc="9. Investors and owner are paid in full">

        // Each investor receives exactly their buying price plus profit.
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, SENIOR_ONE).totalAmountPaid, SENIOR_PER_INVESTOR_TARGET);
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, SENIOR_TWO).totalAmountPaid, SENIOR_PER_INVESTOR_TARGET);
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, JUNIOR_ONE).totalAmountPaid, JUNIOR_PER_INVESTOR_TARGET);
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, JUNIOR_TWO).totalAmountPaid, JUNIOR_PER_INVESTOR_TARGET);

        // The owner receives the promised profit plus the slashed savings: 64 USDC vs a 60 target.
        assertEq(henriable.getOwnerPayoutHistory(INVESTMENT_ID).totalAmountPaid, 64 * USDC_UNIT);
        assertGe(henriable.getOwnerPayoutHistory(INVESTMENT_ID).totalAmountPaid, OWNER_PROFIT);

        // Everything the rider paid (sell price) plus the slashed savings was distributed:
        // 100 senior + 60 junior + 64 owner = 224 = 220 + 4.
        assertEq(henriable.getStats().totalSeniorPayoutsUsd, 100 * USDC_UNIT);
        assertEq(henriable.getStats().totalJuniorPayoutsUsd, 60 * USDC_UNIT);
        assertEq(henriable.getStats().totalOwnerPayoutsUsd, 64 * USDC_UNIT);
        assertEq(
            henriable.getStats().totalSeniorPayoutsUsd + henriable.getStats().totalJuniorPayoutsUsd
                + henriable.getStats().totalOwnerPayoutsUsd,
            SELL_PRICE + 4 * USDC_UNIT
        );

        // Gross rider money in: the 50 buy-in plus four 42 USDC instalments plus the 12 USDC final.
        assertEq(
            henriable.getStats().totalPayinsUsd,
            INITIAL_BUYIN + 4 * (MINIMUM_PAYMENT + SAVINGS_CHARGE)
                + (SELL_PRICE - INITIAL_BUYIN - 4 * MINIMUM_PAYMENT + SAVINGS_CHARGE)
        );
        assertEq(henriable.getStats().investmentsPaidInFull, 1);
        assertEq(henriable.getStats().investmentsInHire, 0);

        //</editor-fold desc="9. Investors and owner are paid in full">
    }

    //<editor-fold desc="Helpers">

    function _asset() internal pure returns (HAsset memory asset) {
        asset = HAsset({
            id: ASSET_ID,
            active: false,
            name: bytes32("Keke-Whole"),
            costPrice: COST_PRICE,
            sellPrice: SELL_PRICE,
            oneSeniorInvestorBuyingPrice: SENIOR_BUYING,
            oneSeniorInvestorProfit: SENIOR_PROFIT,
            oneJuniorInvestorBuyingPrice: JUNIOR_BUYING,
            oneJuniorInvestorProfit: JUNIOR_PROFIT,
            riderSlashableRepayableExtraCharge: SAVINGS_CHARGE,
            ownerProfit: OWNER_PROFIT,
            sharingPercentSeniorInvestor: 50,
            sharingPercentJuniorInvestor: 25,
            sharingPercentOwner: 25,
            sharingPercentJuniorInvestorAfterSeniorPaid: 50,
            sharingPercentOwnerAfterSeniorPaid: 50,
            totalNumberOfSeniorInvestorsNeeded: 2,
            totalNumberOfJuniorInvestorsNeeded: 2
        });
    }

    function _investor() internal pure returns (HInvestor memory) {
        return HInvestor({investorAddress: address(0), name: bytes32("A"), country: bytes32("NG"), age: 30});
    }

    function _fundAndApprove(address who, uint256 amount) internal {
        usdc.mint(who, amount);
        vm.prank(who);
        usdc.approve(address(henriable), type(uint256).max);
    }

    function _invest(address who, HInvestmentType investmentType, uint256 amount) internal {
        _fundAndApprove(who, amount);
        vm.prank(who);
        henriable.actionInvest(_investor(), investmentType, INVESTMENT_ID, amount);
    }

    function _registerRider(address rider) internal {
        _fundAndApprove(rider, 500 * USDC_UNIT);
        vm.prank(rider);
        henriable.actionRiderRegisterAsARider(bytes32("Rider"), bytes32("NG"), 30, INITIAL_BUYIN, INVESTMENT_ID);
    }

    /// @dev Makes one instalment (the hire-purchase minimum plus the savings charge) and asserts
    ///      the next-payment date moved on by exactly one period.
    function _payInstalment(uint256 hirePurchasePortion, uint256 expectedNextPayinDate) internal {
        vm.prank(RIDER_ACCEPTED);
        henriable.actionRiderPayin(INVESTMENT_ID, hirePurchasePortion + SAVINGS_CHARGE);

        assertEq(_nextPayinDate(), expectedNextPayinDate);
    }

    function _status() internal view returns (HInvestmentStatus status) {
        (, , , , , , , status) = henriable.getInvestmentCore(0);
    }

    function _nextPayinDate() internal view returns (uint256 nextPayinDate) {
        (, nextPayinDate, , , ) = henriable.getInvestmentRiderInfo(0);
    }

    //</editor-fold desc="Helpers">
}
