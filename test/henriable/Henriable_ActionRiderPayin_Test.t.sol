// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    HAsset,
    HInvestment,
    HInvestmentDoesNotExist,
    HInvestmentNotHired,
    HInvestmentStatus,
    HInvestmentType,
    HInvestor,
    HInvestorPayout,
    HInvestorPayoutsHistory,
    HInvestmentPayoutsHistory,
    HOwnerPayout,
    HPayingHistory,
    HPayoutType,
    HRiderNotHired,
    HRiderPayin,
    HRiderPayinBelowMinimum,
    HRiderPayinLate,
    HRiderSavingsHistory,
    HStats,
    USDC_UNIT
} from "../../src/types/common.sol";
import {Henriable} from "../../src/Henriable.sol";
import {HenriableVehicleNFT} from "../../src/HenriableVehicleNFT.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";

/// @title Tests for {Henriable.actionRiderPayin}.
/// @notice Covers the hired rider's periodic payment: the amount due (minimum capped by the
///         outstanding balance, plus the asset's refundable savings charge), the split of the
///         hire-purchase portion across the owner and the two investor pools, the savings set
///         aside for the rider, the payment history, and completion once the asset's sell price
///         is fully paid. Also covers every documented revert. Every USD amount is in USDC base
///         units (6 decimals); `USDC_UNIT` is one whole USDC.
/// @dev    The asset needs one senior and one junior slot and has:
///         - costPrice  125, sellPrice 205, ownerProfit 70, savings charge 2
///         - senior: buying 100, profit 5  (pool target 105)
///         - junior: buying  25, profit 5  (pool target  30)
///         - split 70% senior / 25% junior / 5% owner, then 60% junior / 40% owner
///         The investment charges a 10 USDC periodic minimum over 60-minute periods, so the
///         rider owes 12 USDC (10 + 2 savings) per instalment and 7 USDC (5 + 2 savings) on
///         the final instalment, completing after 21 payments (20 x 10 + 5 = 205).
contract HenriableActionRiderPayinTest is Test {
    bytes32 internal constant ASSET_ID = bytes32("keke-0001");
    bytes32 internal constant INVESTMENT_ID = bytes32("inv-0001");
    address internal constant SENIOR = address(0xA11CE);
    address internal constant JUNIOR = address(0xB0B);
    address internal constant RIDER = address(0xB1DE);
    address internal constant OTHER = address(0xDEAD);

    uint256 internal constant MINIMUM_PAYMENT = 10 * USDC_UNIT;
    uint256 internal constant SAVINGS_CHARGE = 2 * USDC_UNIT;
    uint256 internal constant PERIOD = 60 minutes;

    Henriable internal henriable;
    HenriableVehicleNFT internal vehicleNft;
    MockUSDC internal usdc;

    function setUp() public {
        usdc = new MockUSDC();
        vehicleNft = new HenriableVehicleNFT(address(this));
        henriable = new Henriable(address(this), IERC20(address(usdc)), vehicleNft);
        vehicleNft.setMinter(address(henriable));

        henriable.actionAdminAddAsset(_validAsset());
        henriable.actionAdminAddInvestment(INVESTMENT_ID, ASSET_ID, 50 * USDC_UNIT, 60, MINIMUM_PAYMENT);

        // Open the investment round, fill both pools so the opportunity is funded.
        uint256 start = block.timestamp + 10;
        henriable.actionAdminSetNextInvestmentTimes(INVESTMENT_ID, start, start + 1 days);
        vm.warp(start + 1);

        _fundAndApprove(SENIOR);
        _fundAndApprove(JUNIOR);
        vm.prank(SENIOR);
        henriable.actionInvest(_investor(), HInvestmentType.Senior, INVESTMENT_ID, 100 * USDC_UNIT);
        vm.prank(JUNIOR);
        henriable.actionInvest(_investor(), HInvestmentType.Junior, INVESTMENT_ID, 25 * USDC_UNIT);

        // Open the hire round, register the rider and accept them so the purchase runs.
        uint256 hireStart = block.timestamp + 10;
        henriable.actionSetNextHireRoundTime(INVESTMENT_ID, hireStart, hireStart + 1 days);
        vm.warp(hireStart + 1);

        _fundAndApprove(RIDER);
        vm.prank(RIDER);
        henriable.actionRiderRegisterAsARider(bytes32("Rider"), bytes32("NG"), 30, 50 * USDC_UNIT, INVESTMENT_ID);
        henriable.actionAdminAcceptRider(INVESTMENT_ID, RIDER);
    }

    /// @notice Builds an asset needing one senior and one junior slot whose sell price exactly
    ///         covers the investor principal, their profits and the owner's profit.
    function _validAsset() internal pure returns (HAsset memory asset) {
        asset = HAsset({
            id: ASSET_ID,
            active: false,
            name: bytes32("Keke"),
            costPrice: 125 * USDC_UNIT,
            sellPrice: 205 * USDC_UNIT,
            oneSeniorInvestorBuyingPrice: 100 * USDC_UNIT,
            oneSeniorInvestorProfit: 5 * USDC_UNIT,
            oneJuniorInvestorBuyingPrice: 25 * USDC_UNIT,
            oneJuniorInvestorProfit: 5 * USDC_UNIT,
            riderSlashableRepayableExtraCharge: SAVINGS_CHARGE,
            ownerProfit: 70 * USDC_UNIT,
            sharingPercentSeniorInvestor: 70,
            sharingPercentJuniorInvestor: 25,
            sharingPercentOwner: 5,
            sharingPercentJuniorInvestorAfterSeniorPaid: 60,
            sharingPercentOwnerAfterSeniorPaid: 40,
            totalNumberOfSeniorInvestorsNeeded: 1,
            totalNumberOfJuniorInvestorsNeeded: 1
        });
    }

    function _investor() internal pure returns (HInvestor memory) {
        return HInvestor({investorAddress: address(0), name: bytes32("A"), country: bytes32("NG"), age: 30});
    }

    function _fundAndApprove(address who) internal {
        usdc.mint(who, 1_000 * USDC_UNIT);
        vm.prank(who);
        usdc.approve(address(henriable), type(uint256).max);
    }

    function _nextPayinDate() internal view returns (uint256 nextPayinDate) {
        (, nextPayinDate, , , ) = henriable.getInvestmentRiderInfo(0);
    }

    function _status() internal view returns (HInvestmentStatus status) {
        (, , , , , , , status) = henriable.getInvestmentCore(0);
    }

    function _payMinimum() internal {
        vm.prank(RIDER);
        henriable.actionRiderPayin(INVESTMENT_ID, MINIMUM_PAYMENT + SAVINGS_CHARGE);
    }

    //<editor-fold desc="Happy path: first payment">

    function test_ActionRiderPayin_RecordsPaymentEntry() public {
        _payMinimum();

        assertEq(henriable.getRiderPayinsCount(), 1);

        HRiderPayin memory payin = henriable.getRiderPayinAt(0);
        assertEq(payin.riderId, bytes32(uint256(uint160(RIDER))));
        assertEq(payin.investmentId, INVESTMENT_ID);
        assertEq(payin.amountPaid, MINIMUM_PAYMENT + SAVINGS_CHARGE);
        assertEq(payin.timePaid, block.timestamp);
        assertEq(payin.addressPaidInto, address(henriable));

        uint256[] memory indexes = henriable.getRiderPayinIndexes(INVESTMENT_ID);
        assertEq(indexes.length, 1);
        assertEq(indexes[0], 1);
    }

    /// @notice Only the hire-purchase portion (payment minus the refundable savings charge)
    ///         counts toward the paying history; the savings charge does not reduce what the
    ///         rider still owes.
    function test_ActionRiderPayin_CountsOnlyHirePurchasePortion_InHistory() public {
        _payMinimum();

        HPayingHistory memory history = henriable.getInvestmentRiderPayinsHistory(0);
        assertEq(history.riderAddress, RIDER);
        assertEq(history.totalAmountPaid, MINIMUM_PAYMENT);
        assertEq(history.totalNumberOfTimesPaid, 1);
    }

    function test_ActionRiderPayin_AdvancesNextPayinDateByOnePeriod() public {
        uint256 before = _nextPayinDate();

        _payMinimum();

        assertEq(_nextPayinDate(), before + PERIOD);
    }

    function test_ActionRiderPayin_SetsSavingsChargeAside() public {
        uint256 riderBalanceBefore = usdc.balanceOf(RIDER);
        uint256 contractBalanceBefore = usdc.balanceOf(address(henriable));

        _payMinimum();

        HRiderSavingsHistory memory savings = henriable.getInvestmentRiderSavings(0);
        assertEq(savings.riderAddress, RIDER);
        assertEq(savings.totalAmountSaved, SAVINGS_CHARGE);
        assertEq(savings.savings.length, 1);
        assertEq(savings.savings[0].amountSaved, SAVINGS_CHARGE);
        assertEq(savings.savings[0].timeSaved, block.timestamp);

        // The rider pays the full instalment; the contract only keeps the savings, since the
        // rest is paid straight out to the owner and the pools.
        assertEq(riderBalanceBefore - usdc.balanceOf(RIDER), MINIMUM_PAYMENT + SAVINGS_CHARGE);
        assertEq(usdc.balanceOf(address(henriable)) - contractBalanceBefore, SAVINGS_CHARGE);
    }

    function test_ActionRiderPayin_SplitsPayment_AcrossOwnerAndPools() public {
        uint256 seniorBefore = usdc.balanceOf(SENIOR);
        uint256 juniorBefore = usdc.balanceOf(JUNIOR);
        uint256 ownerBefore = usdc.balanceOf(address(this));

        _payMinimum();

        // 10 USDC hire-purchase portion split 70/25/5 while the senior pool is owed.
        assertEq(usdc.balanceOf(SENIOR) - seniorBefore, 7 * USDC_UNIT);
        assertEq(usdc.balanceOf(JUNIOR) - juniorBefore, 2_500_000);
        assertEq(usdc.balanceOf(address(this)) - ownerBefore, 500_000);
    }

    function test_ActionRiderPayin_RecordsPayoutHistories() public {
        _payMinimum();

        HOwnerPayout memory ownerPayout = henriable.getOwnerPayoutAt(0);
        assertEq(uint256(ownerPayout.payoutType), uint256(HPayoutType.RiderPaying));
        assertEq(ownerPayout.amountPaid, 500_000);
        assertEq(henriable.getOwnerPayoutIndex(INVESTMENT_ID), 1);
        assertEq(henriable.getOwnerPayoutHistory(INVESTMENT_ID).totalAmountPaid, 500_000);

        assertEq(henriable.getInvestorPayoutsCount(), 2);
        HInvestorPayout memory seniorPayout = henriable.getInvestorPayoutAt(0);
        assertEq(uint256(seniorPayout.payoutType), uint256(HPayoutType.RiderPaying));
        assertEq(seniorPayout.addressPaidInto, SENIOR);
        assertEq(seniorPayout.amountPaid, 7 * USDC_UNIT);

        HInvestorPayout memory juniorPayout = henriable.getInvestorPayoutAt(1);
        assertEq(juniorPayout.addressPaidInto, JUNIOR);
        assertEq(juniorPayout.amountPaid, 2_500_000);

        HInvestorPayoutsHistory memory seniorHistory = henriable.getInvestorPayoutHistory(INVESTMENT_ID, SENIOR);
        assertEq(seniorHistory.totalAmountPaid, 7 * USDC_UNIT);
        assertEq(seniorHistory.totalNumberOfTimesPaid, 1);

        HInvestmentPayoutsHistory memory investmentHistory = henriable.getInvestmentPayoutHistory(0);
        assertEq(investmentHistory.investmentId, INVESTMENT_ID);
        assertEq(investmentHistory.totalAmountPaid, 10 * USDC_UNIT);
        assertEq(investmentHistory.totalNumberOfTimesPaid, 1);
    }

    function test_ActionRiderPayin_UpdatesPlatformStats() public {
        _payMinimum();

        HStatsView memory s = _stats();
        assertEq(s.totalPayinsUsd, MINIMUM_PAYMENT + SAVINGS_CHARGE);
        assertEq(s.totalOwnerPayoutsUsd, 500_000);
        assertEq(s.totalSeniorPayoutsUsd, 7 * USDC_UNIT);
        assertEq(s.totalJuniorPayoutsUsd, 2_500_000);
        assertEq(s.riderSavingsHeldUsd, SAVINGS_CHARGE);
    }

    //</editor-fold desc="Happy path: first payment">

    //<editor-fold desc="Happy path: multi-period">

    /// @notice Once the senior pool has received its full target (105 USDC), later payments
    ///         switch to the after-senior split: 60% junior / 40% owner.
    function test_ActionRiderPayin_SwitchesToJuniorSplit_WhenSeniorPaidOff() public {
        // 15 payments of 10 USDC hire-purchase portion deliver 7 USDC each to senior = 105.
        for (uint256 i = 0; i < 15; i++) {
            _payMinimum();
        }

        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, SENIOR).totalAmountPaid, 105 * USDC_UNIT);

        uint256 ownerBefore = usdc.balanceOf(address(this));
        uint256 juniorBefore = usdc.balanceOf(JUNIOR);
        uint256 payoutsBefore = henriable.getInvestorPayoutsCount();

        _payMinimum();

        // The 16th payment goes 60% to junior and 40% to the owner; senior gets nothing, so
        // no senior payout entry is recorded.
        assertEq(usdc.balanceOf(JUNIOR) - juniorBefore, 6 * USDC_UNIT);
        assertEq(usdc.balanceOf(address(this)) - ownerBefore, 4 * USDC_UNIT);
        assertEq(henriable.getInvestorPayoutsCount(), payoutsBefore + 1);

        HInvestorPayout memory lastPayout = henriable.getInvestorPayoutAt(payoutsBefore);
        assertEq(lastPayout.addressPaidInto, JUNIOR);
        assertEq(lastPayout.amountPaid, 6 * USDC_UNIT);
    }

    //</editor-fold desc="Happy path: multi-period">

    //<editor-fold desc="Completion">

    function test_ActionRiderPayin_CompletesAndTransfersOwnership_OnFinalInstalment() public {
        // 20 full instalments: 20 x (10 + 2) = 240 paid, 200 hire-purchase, 5 outstanding.
        for (uint256 i = 0; i < 20; i++) {
            _payMinimum();
            assertEq(uint256(_status()), uint256(HInvestmentStatus.Hired));
        }

        uint256 savingsBeforeFinal = 20 * SAVINGS_CHARGE;
        assertEq(henriable.getInvestmentRiderSavings(0).totalAmountSaved, savingsBeforeFinal);

        uint256 riderBalanceBefore = usdc.balanceOf(RIDER);

        // Final instalment: the periodic minimum is capped by the 5 USDC outstanding balance,
        // plus the 2 USDC savings charge.
        vm.prank(RIDER);
        henriable.actionRiderPayin(INVESTMENT_ID, 5 * USDC_UNIT + SAVINGS_CHARGE);

        HPayingHistory memory history = henriable.getInvestmentRiderPayinsHistory(0);
        assertEq(history.totalAmountPaid, 205 * USDC_UNIT);
        assertEq(history.totalNumberOfTimesPaid, 21);

        // The rider's accumulated savings are refunded and cleared on completion.
        assertEq(henriable.getInvestmentRiderSavings(0).totalAmountSaved, 0);
        assertEq(_stats().riderSavingsHeldUsd, 0);

        // Final instalment pulls in 7 USDC and hands back all 42 USDC of accumulated savings.
        uint256 totalSavingsRefunded = savingsBeforeFinal + SAVINGS_CHARGE;
        assertEq(usdc.balanceOf(RIDER) - riderBalanceBefore, totalSavingsRefunded - (5 * USDC_UNIT + SAVINGS_CHARGE));

        // The investment is complete, the completion times are recorded and listed.
        assertEq(uint256(_status()), uint256(HInvestmentStatus.Complete));

        (address riderWhoHiredIt, , , uint256 completedAt, uint256 transferredAt) =
            henriable.getInvestmentRiderInfo(0);
        assertEq(riderWhoHiredIt, RIDER);
        assertEq(completedAt, block.timestamp);
        assertEq(transferredAt, block.timestamp);

        assertEq(henriable.getCompletedRiderInvestmentsCount(), 1);
        assertEq(henriable.getCompletedRiderInvestmentAt(0), 1);
        assertEq(henriable.getInvestmentsCompletedCount(), 1);
        assertEq(henriable.getInvestmentsCompletedAt(0), 1);
        assertEq(_stats().investmentsPaidInFull, 1);

        // The vehicle title, held by the platform while the rider paid, is now the rider's.
        (, , uint256 nftTokenId, , ) = henriable.getInvestmentRiderInfo(0);
        assertEq(nftTokenId, 1);
        assertEq(vehicleNft.ownerOf(nftTokenId), RIDER);
    }

    function test_ActionRiderPayin_Reverts_AfterCompletion() public {
        for (uint256 i = 0; i < 20; i++) {
            _payMinimum();
        }
        vm.prank(RIDER);
        henriable.actionRiderPayin(INVESTMENT_ID, 5 * USDC_UNIT + SAVINGS_CHARGE);

        // The status is no longer Hired, so no further payment is accepted.
        vm.prank(RIDER);
        vm.expectRevert(abi.encodeWithSelector(HInvestmentNotHired.selector, INVESTMENT_ID));
        henriable.actionRiderPayin(INVESTMENT_ID, MINIMUM_PAYMENT + SAVINGS_CHARGE);
    }

    //</editor-fold desc="Completion">

    //<editor-fold desc="Reverts">

    function test_ActionRiderPayin_Reverts_WhenInvestmentDoesNotExist() public {
        vm.prank(RIDER);
        vm.expectRevert(abi.encodeWithSelector(HInvestmentDoesNotExist.selector, bytes32("missing")));
        henriable.actionRiderPayin(bytes32("missing"), MINIMUM_PAYMENT + SAVINGS_CHARGE);
    }

    function test_ActionRiderPayin_Reverts_WhenNotHired() public {
        bytes32 idleId = bytes32("inv-idle");
        henriable.actionAdminAddInvestment(idleId, ASSET_ID, 50 * USDC_UNIT, 60, MINIMUM_PAYMENT);

        vm.prank(RIDER);
        vm.expectRevert(abi.encodeWithSelector(HInvestmentNotHired.selector, idleId));
        henriable.actionRiderPayin(idleId, MINIMUM_PAYMENT + SAVINGS_CHARGE);
    }

    function test_ActionRiderPayin_Reverts_WhenCallerIsNotTheHiredRider() public {
        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(HRiderNotHired.selector, INVESTMENT_ID, OTHER));
        henriable.actionRiderPayin(INVESTMENT_ID, MINIMUM_PAYMENT + SAVINGS_CHARGE);
    }

    function test_ActionRiderPayin_Reverts_WhenBelowMinimum() public {
        vm.prank(RIDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                HRiderPayinBelowMinimum.selector, MINIMUM_PAYMENT + SAVINGS_CHARGE - 1, MINIMUM_PAYMENT + SAVINGS_CHARGE
            )
        );
        henriable.actionRiderPayin(INVESTMENT_ID, MINIMUM_PAYMENT + SAVINGS_CHARGE - 1);
    }

    function test_ActionRiderPayin_Reverts_WhenLate() public {
        vm.warp(_nextPayinDate() + 1);

        vm.prank(RIDER);
        vm.expectRevert(abi.encodeWithSelector(HRiderPayinLate.selector, INVESTMENT_ID));
        henriable.actionRiderPayin(INVESTMENT_ID, MINIMUM_PAYMENT + SAVINGS_CHARGE);
    }

    function test_ActionRiderPayin_Succeeds_WhenOnTime() public {
        // Paying exactly on the due date is accepted.
        vm.warp(_nextPayinDate());

        _payMinimum();

        assertEq(henriable.getInvestmentRiderPayinsHistory(0).totalNumberOfTimesPaid, 1);
    }

    //</editor-fold desc="Reverts">

    //<editor-fold desc="Helpers">

    /// @dev Local mirror of {HStats} limited to the fields asserted here, to keep the tests
    ///      readable without importing the whole struct.
    struct HStatsView {
        uint256 totalPayinsUsd;
        uint256 totalSeniorPayoutsUsd;
        uint256 totalJuniorPayoutsUsd;
        uint256 totalOwnerPayoutsUsd;
        uint256 riderSavingsHeldUsd;
        uint256 investmentsPaidInFull;
    }

    function _stats() internal view returns (HStatsView memory s) {
        HStats memory platform = henriable.getStats();
        s.totalPayinsUsd = platform.totalPayinsUsd;
        s.totalSeniorPayoutsUsd = platform.totalSeniorPayoutsUsd;
        s.totalJuniorPayoutsUsd = platform.totalJuniorPayoutsUsd;
        s.totalOwnerPayoutsUsd = platform.totalOwnerPayoutsUsd;
        s.riderSavingsHeldUsd = platform.riderSavingsHeldUsd;
        s.investmentsPaidInFull = platform.investmentsPaidInFull;
    }

    //</editor-fold desc="Helpers">
}
