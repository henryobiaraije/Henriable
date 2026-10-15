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
/// @notice Covers the hired rider's periodic payment with target-driven, waterfall payouts: each
///         payment first fills the senior pool to its buying price plus profit, then the junior
///         pool, and the owner receives the rest. The accepted rider's initial buy-in was already
///         credited (and shared) at accept time, so it counts toward the rider's total here.
///         Every USD amount is in USDC base units (6 decimals). The asset needs one senior and
///         one junior seat:
///         - senior buying 100 + profit 5  => pool target 105
///         - junior buying  25 + profit 5  => pool target  30
///         - ownerProfit 70, sellPrice 205, savings charge 2, initial buy-in 50
///         So the buy-in sends 50 to senior, then 15 instalments of 10 plus a final 5 clear the
///         remaining 155, across 16 periodic payments.
contract HenriableActionRiderPayinTest is Test {
    bytes32 internal constant ASSET_ID = bytes32("keke-0001");
    bytes32 internal constant INVESTMENT_ID = bytes32("inv-0001");
    address internal constant SENIOR = address(0xA11CE);
    address internal constant JUNIOR = address(0xB0B);
    address internal constant RIDER = address(0xB1DE);
    address internal constant OTHER = address(0xDEAD);

    uint256 internal constant MINIMUM_PAYMENT = 10 * USDC_UNIT;
    uint256 internal constant SAVINGS_CHARGE = 2 * USDC_UNIT;
    uint256 internal constant INSTALMENT = MINIMUM_PAYMENT + SAVINGS_CHARGE;
    uint256 internal constant INITIAL_BUYIN = 50 * USDC_UNIT;
    uint256 internal constant SELL_PRICE = 205 * USDC_UNIT;
    uint256 internal constant SENIOR_TARGET = 105 * USDC_UNIT;
    uint256 internal constant JUNIOR_TARGET = 30 * USDC_UNIT;
    uint256 internal constant OWNER_PROFIT = 70 * USDC_UNIT;
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
        henriable.actionAdminAddInvestment(INVESTMENT_ID, ASSET_ID, INITIAL_BUYIN, 60, MINIMUM_PAYMENT);

        uint256 start = block.timestamp + 10;
        henriable.actionAdminSetNextInvestmentTimes(INVESTMENT_ID, start, start + 1 days);
        vm.warp(start + 1);

        _fundAndApprove(SENIOR);
        _fundAndApprove(JUNIOR);
        vm.prank(SENIOR);
        henriable.actionInvest(_investor(), HInvestmentType.Senior, INVESTMENT_ID, 100 * USDC_UNIT);
        vm.prank(JUNIOR);
        henriable.actionInvest(_investor(), HInvestmentType.Junior, INVESTMENT_ID, 25 * USDC_UNIT);

        uint256 hireStart = block.timestamp + 10;
        henriable.actionSetNextHireRoundTime(INVESTMENT_ID, hireStart, hireStart + 1 days);
        vm.warp(hireStart + 1);

        _fundAndApprove(RIDER);
        vm.prank(RIDER);
        henriable.actionRiderRegisterAsARider(bytes32("Rider"), bytes32("NG"), 30, INITIAL_BUYIN, INVESTMENT_ID);
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
            sellPrice: SELL_PRICE,
            oneSeniorInvestorBuyingPrice: 100 * USDC_UNIT,
            oneSeniorInvestorProfit: 5 * USDC_UNIT,
            oneJuniorInvestorBuyingPrice: 25 * USDC_UNIT,
            oneJuniorInvestorProfit: 5 * USDC_UNIT,
            riderSlashableRepayableExtraCharge: SAVINGS_CHARGE,
            ownerProfit: OWNER_PROFIT,
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

    function _pay(uint256 amount) internal {
        vm.prank(RIDER);
        henriable.actionRiderPayin(INVESTMENT_ID, amount);
    }

    function _payInstalment() internal {
        _pay(INSTALMENT);
    }

    //<editor-fold desc="Happy path: first periodic payment">

    function test_ActionRiderPayin_RecordsPaymentEntry() public {
        _payInstalment();

        assertEq(henriable.getRiderPayinsCount(), 1);

        HRiderPayin memory payin = henriable.getRiderPayinAt(0);
        assertEq(payin.riderId, bytes32(uint256(uint160(RIDER))));
        assertEq(payin.investmentId, INVESTMENT_ID);
        assertEq(payin.amountPaid, INSTALMENT);
        assertEq(payin.timePaid, block.timestamp);
        assertEq(payin.addressPaidInto, address(henriable));

        uint256[] memory indexes = henriable.getRiderPayinIndexes(INVESTMENT_ID);
        assertEq(indexes.length, 1);
        assertEq(indexes[0], 1);
    }

    /// @notice Only the hire-purchase portion of a periodic payment (payment minus the savings
    ///         charge) counts toward the paying history, on top of the credited initial buy-in.
    function test_ActionRiderPayin_CountsHirePurchasePortion_OnTopOfBuyin() public {
        _payInstalment();

        HPayingHistory memory history = henriable.getInvestmentRiderPayinsHistory(0);
        assertEq(history.riderAddress, RIDER);
        assertEq(history.totalAmountPaid, INITIAL_BUYIN + MINIMUM_PAYMENT);
        assertEq(history.totalNumberOfTimesPaid, 1);
    }

    function test_ActionRiderPayin_AdvancesNextPayinDateByOnePeriod() public {
        uint256 before = _nextPayinDate();

        _payInstalment();

        assertEq(_nextPayinDate(), before + PERIOD);
    }

    function test_ActionRiderPayin_SetsSavingsChargeAside() public {
        uint256 riderBalanceBefore = usdc.balanceOf(RIDER);
        uint256 contractBalanceBefore = usdc.balanceOf(address(henriable));

        _payInstalment();

        HRiderSavingsHistory memory savings = henriable.getInvestmentRiderSavings(0);
        assertEq(savings.riderAddress, RIDER);
        assertEq(savings.totalAmountSaved, SAVINGS_CHARGE);
        assertEq(savings.savings.length, 1);
        assertEq(savings.savings[0].amountSaved, SAVINGS_CHARGE);

        // The rider pays the whole instalment; the contract keeps only the savings because the
        // hire-purchase portion is paid straight to the senior pool.
        assertEq(riderBalanceBefore - usdc.balanceOf(RIDER), INSTALMENT);
        assertEq(usdc.balanceOf(address(henriable)) - contractBalanceBefore, SAVINGS_CHARGE);
    }

    /// @notice The first periodic payment goes entirely to senior, which is still owed after the
    ///         initial buy-in.
    function test_ActionRiderPayin_PaysSeniorFirst() public {
        uint256 seniorBefore = usdc.balanceOf(SENIOR);
        uint256 juniorBefore = usdc.balanceOf(JUNIOR);
        uint256 ownerBefore = usdc.balanceOf(address(this));

        _payInstalment();

        assertEq(usdc.balanceOf(SENIOR) - seniorBefore, MINIMUM_PAYMENT);
        assertEq(usdc.balanceOf(JUNIOR) - juniorBefore, 0);
        assertEq(usdc.balanceOf(address(this)) - ownerBefore, 0);
    }

    function test_ActionRiderPayin_RecordsPayoutHistories() public {
        // The buy-in already recorded one senior payout of 50, so counts start at one.
        _payInstalment();

        assertEq(henriable.getOwnerPayoutsCount(), 0);

        assertEq(henriable.getInvestorPayoutsCount(), 2);
        HInvestorPayout memory buyinPayout = henriable.getInvestorPayoutAt(0);
        assertEq(buyinPayout.addressPaidInto, SENIOR);
        assertEq(buyinPayout.amountPaid, INITIAL_BUYIN);

        HInvestorPayout memory seniorPayout = henriable.getInvestorPayoutAt(1);
        assertEq(uint256(seniorPayout.payoutType), uint256(HPayoutType.RiderPaying));
        assertEq(seniorPayout.addressPaidInto, SENIOR);
        assertEq(seniorPayout.amountPaid, MINIMUM_PAYMENT);

        HInvestorPayoutsHistory memory seniorHistory = henriable.getInvestorPayoutHistory(INVESTMENT_ID, SENIOR);
        assertEq(seniorHistory.totalAmountPaid, INITIAL_BUYIN + MINIMUM_PAYMENT);
        assertEq(seniorHistory.totalNumberOfTimesPaid, 2);

        HInvestmentPayoutsHistory memory investmentHistory = henriable.getInvestmentPayoutHistory(0);
        assertEq(investmentHistory.investmentId, INVESTMENT_ID);
        assertEq(investmentHistory.totalAmountPaid, INITIAL_BUYIN + MINIMUM_PAYMENT);
        assertEq(investmentHistory.totalNumberOfTimesPaid, 2);
    }

    function test_ActionRiderPayin_UpdatesPlatformStats() public {
        _payInstalment();

        HStatsView memory s = _stats();
        assertEq(s.totalPayinsUsd, INITIAL_BUYIN + INSTALMENT);
        assertEq(s.totalOwnerPayoutsUsd, 0);
        assertEq(s.totalSeniorPayoutsUsd, INITIAL_BUYIN + MINIMUM_PAYMENT);
        assertEq(s.totalJuniorPayoutsUsd, 0);
        assertEq(s.riderSavingsHeldUsd, SAVINGS_CHARGE);
    }

    //</editor-fold desc="Happy path: first periodic payment">

    //<editor-fold desc="Happy path: waterfall transitions">

    /// @notice Senior is filled first: the first five instalments complete its remaining target,
    ///         then the sixth spills to junior.
    function test_ActionRiderPayin_SpillsToJunior_WhenSeniorPaidOff() public {
        for (uint256 i = 0; i < 5; i++) {
            _payInstalment();
        }
        // 50 from the buy-in plus five 10 USDC instalments leaves senior 5 USDC short.
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, SENIOR).totalAmountPaid, SENIOR_TARGET - 5 * USDC_UNIT);

        uint256 seniorBefore = usdc.balanceOf(SENIOR);
        uint256 juniorBefore = usdc.balanceOf(JUNIOR);
        uint256 ownerBefore = usdc.balanceOf(address(this));

        // Senior needs 5 more, so this 10 USDC instalment sends 5 to senior and 5 to junior.
        _payInstalment();

        assertEq(usdc.balanceOf(SENIOR) - seniorBefore, 5 * USDC_UNIT);
        assertEq(usdc.balanceOf(JUNIOR) - juniorBefore, 5 * USDC_UNIT);
        assertEq(usdc.balanceOf(address(this)) - ownerBefore, 0);
    }

    /// @notice Once both pools are paid, further instalments go to the owner.
    function test_ActionRiderPayin_PaysOwner_WhenBothPoolsPaid() public {
        // 6 instalments finish senior; 3 more finish junior (5 + 10 + 10 + 5 = 30).
        for (uint256 i = 0; i < 9; i++) {
            _payInstalment();
        }
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, SENIOR).totalAmountPaid, SENIOR_TARGET);
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, JUNIOR).totalAmountPaid, JUNIOR_TARGET);

        uint256 ownerBefore = usdc.balanceOf(address(this));

        _payInstalment();

        assertEq(usdc.balanceOf(address(this)) - ownerBefore, MINIMUM_PAYMENT);
    }

    //</editor-fold desc="Happy path: waterfall transitions">

    //<editor-fold desc="Completion">

    function test_ActionRiderPayin_CompletesAndTransfersOwnership_OnFinalInstalment() public {
        // 15 full instalments (10 hire-purchase each) bring the rider to 200 of the 205 owed.
        for (uint256 i = 0; i < 15; i++) {
            _payInstalment();
            assertEq(uint256(_status()), uint256(HInvestmentStatus.Hired));
        }

        uint256 savingsBeforeFinal = 15 * SAVINGS_CHARGE;
        assertEq(henriable.getInvestmentRiderSavings(0).totalAmountSaved, savingsBeforeFinal);

        uint256 riderBalanceBefore = usdc.balanceOf(RIDER);

        // Final instalment: the periodic minimum is capped by the 5 USDC outstanding balance,
        // plus the 2 USDC savings charge.
        _pay(5 * USDC_UNIT + SAVINGS_CHARGE);

        HPayingHistory memory history = henriable.getInvestmentRiderPayinsHistory(0);
        assertEq(history.totalAmountPaid, SELL_PRICE);
        assertEq(history.totalNumberOfTimesPaid, 16);

        // Pools and owner land exactly on their promises.
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, SENIOR).totalAmountPaid, SENIOR_TARGET);
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, JUNIOR).totalAmountPaid, JUNIOR_TARGET);
        assertEq(henriable.getOwnerPayoutHistory(INVESTMENT_ID).totalAmountPaid, OWNER_PROFIT);
        assertEq(henriable.getInvestmentPayoutHistory(0).totalAmountPaid, SELL_PRICE);

        // The rider's accumulated savings are refunded and cleared on completion.
        assertEq(henriable.getInvestmentRiderSavings(0).totalAmountSaved, 0);
        assertEq(_stats().riderSavingsHeldUsd, 0);
        uint256 totalSavingsRefunded = savingsBeforeFinal + SAVINGS_CHARGE;
        assertEq(usdc.balanceOf(RIDER) - riderBalanceBefore, totalSavingsRefunded - (5 * USDC_UNIT + SAVINGS_CHARGE));

        // The investment is complete, the completion times are recorded and listed.
        assertEq(uint256(_status()), uint256(HInvestmentStatus.Complete));
        (address riderWhoHiredIt, , uint256 nftTokenId, uint256 completedAt, uint256 transferredAt) =
            henriable.getInvestmentRiderInfo(0);
        assertEq(riderWhoHiredIt, RIDER);
        assertEq(completedAt, block.timestamp);
        assertEq(transferredAt, block.timestamp);
        assertEq(vehicleNft.ownerOf(nftTokenId), RIDER);

        assertEq(henriable.getCompletedRiderInvestmentsCount(), 1);
        assertEq(henriable.getInvestmentsCompletedCount(), 1);
        assertEq(henriable.getStats().investmentsPaidInFull, 1);
    }

    function test_ActionRiderPayin_Reverts_AfterCompletion() public {
        for (uint256 i = 0; i < 15; i++) {
            _payInstalment();
        }
        _pay(5 * USDC_UNIT + SAVINGS_CHARGE);

        // The status is no longer Hired, so no further payment is accepted.
        vm.prank(RIDER);
        vm.expectRevert(abi.encodeWithSelector(HInvestmentNotHired.selector, INVESTMENT_ID));
        henriable.actionRiderPayin(INVESTMENT_ID, INSTALMENT);
    }

    //</editor-fold desc="Completion">

    //<editor-fold desc="Reverts">

    function test_ActionRiderPayin_Reverts_WhenInvestmentDoesNotExist() public {
        vm.prank(RIDER);
        vm.expectRevert(abi.encodeWithSelector(HInvestmentDoesNotExist.selector, bytes32("missing")));
        henriable.actionRiderPayin(bytes32("missing"), INSTALMENT);
    }

    function test_ActionRiderPayin_Reverts_WhenNotHired() public {
        bytes32 idleId = bytes32("inv-idle");
        henriable.actionAdminAddInvestment(idleId, ASSET_ID, INITIAL_BUYIN, 60, MINIMUM_PAYMENT);

        vm.prank(RIDER);
        vm.expectRevert(abi.encodeWithSelector(HInvestmentNotHired.selector, idleId));
        henriable.actionRiderPayin(idleId, INSTALMENT);
    }

    function test_ActionRiderPayin_Reverts_WhenCallerIsNotTheHiredRider() public {
        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(HRiderNotHired.selector, INVESTMENT_ID, OTHER));
        henriable.actionRiderPayin(INVESTMENT_ID, INSTALMENT);
    }

    function test_ActionRiderPayin_Reverts_WhenBelowMinimum() public {
        vm.prank(RIDER);
        vm.expectRevert(abi.encodeWithSelector(HRiderPayinBelowMinimum.selector, INSTALMENT - 1, INSTALMENT));
        henriable.actionRiderPayin(INVESTMENT_ID, INSTALMENT - 1);
    }

    function test_ActionRiderPayin_Reverts_WhenLate() public {
        vm.warp(_nextPayinDate() + 1);

        vm.prank(RIDER);
        vm.expectRevert(abi.encodeWithSelector(HRiderPayinLate.selector, INVESTMENT_ID));
        henriable.actionRiderPayin(INVESTMENT_ID, INSTALMENT);
    }

    function test_ActionRiderPayin_Succeeds_WhenOnTime() public {
        vm.warp(_nextPayinDate());

        _payInstalment();

        assertEq(henriable.getInvestmentRiderPayinsHistory(0).totalNumberOfTimesPaid, 1);
    }

    //</editor-fold desc="Reverts">

    //<editor-fold desc="Helpers">

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
