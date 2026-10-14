// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    HAsset,
    HInvestmentInvalidRiderNextPayinDate,
    HInvestmentNotHired,
    HInvestmentStatus,
    HInvestmentType,
    HInvestor,
    HInvestorPayout,
    HOwnerPayout,
    HPayoutType,
    HRiderSavingsSlash,
    HRiderSavingsSlashExceedsSaved,
    USDC_UNIT
} from "../../src/types/common.sol";
import {Henriable} from "../../src/Henriable.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";

/// @title Tests for {Henriable.actionAdminExtendRiderPayingForInvestment}.
/// @notice Covers extending the hired rider's next payment due date: only an owner may
///         call, the hire purchase must be running, and the new date must be later than
///         the current one. Every USD amount is in USDC base units (6 decimals).
/// @dev    Deploys {Henriable} rather than inheriting it because Henriable's public demo
///         functions (`testSet`) would otherwise be fuzzed as tests and fail.
contract HenriableActionAdminExtendRiderPayingForInvestmentTest is Test {
    bytes32 internal constant ASSET_ID = bytes32("keke-0001");
    bytes32 internal constant INVESTMENT_ID = bytes32("inv-0001");
    address internal constant SENIOR = address(0xA11CE);
    address internal constant JUNIOR = address(0xB0B);
    address internal constant RIDER = address(0xB1DE);
    address internal constant OWNER_2 = address(0xBEEF);
    address internal constant NON_OWNER = address(0xDEAD);

    Henriable internal henriable;
    MockUSDC internal usdc;

    function setUp() public {
        usdc = new MockUSDC();
        henriable = new Henriable(address(this), IERC20(address(usdc)));

        henriable.actionAdminAddAsset(_validAsset());
        henriable.actionAdminAddInvestment(INVESTMENT_ID, ASSET_ID, 50 * USDC_UNIT, 60, 10 * USDC_UNIT);

        // Open and fill the investment round so the opportunity is fully funded.
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

    /// @notice Builds a correct asset that needs one senior and one junior slot.
    function _validAsset() internal pure returns (HAsset memory asset) {
        asset = HAsset({
            id: ASSET_ID,
            active: false,
            name: bytes32("Keke"),
            costPrice: 125 * USDC_UNIT,
            sellPrice: 210 * USDC_UNIT,
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

    /// @dev The asset's per-period savings charge is 2 USDC, so one minimum payment (10 USDC
    ///      + 2 USDC savings) leaves the rider with 2 USDC of refundable savings to slash.
    function _makeRiderPayin() internal {
        vm.prank(RIDER);
        henriable.actionRiderPayin(INVESTMENT_ID, 12 * USDC_UNIT);
    }

    //<editor-fold desc="Happy path">

    function test_ActionAdminExtendRiderPayingForInvestment_ExtendsNextPayinDate_WhenHired() public {
        uint256 currentPayinDate = _nextPayinDate();
        uint256 newPayinDate = currentPayinDate + 2 days;

        henriable.actionAdminExtendRiderPayingForInvestment(INVESTMENT_ID, newPayinDate, 0);

        assertEq(_nextPayinDate(), newPayinDate);
    }

    function test_ActionAdminExtendRiderPayingForInvestment_AllowsOwner2() public {
        henriable.actionAdminSetOwner2(OWNER_2);
        uint256 newPayinDate = _nextPayinDate() + 1 days;

        vm.prank(OWNER_2);
        henriable.actionAdminExtendRiderPayingForInvestment(INVESTMENT_ID, newPayinDate, 0);

        assertEq(_nextPayinDate(), newPayinDate);
    }

    //</editor-fold desc="Happy path">

    //<editor-fold desc="Reverts">

    function test_ActionAdminExtendRiderPayingForInvestment_Reverts_WhenCallerIsNotAnOwner() public {
        uint256 newPayinDate = _nextPayinDate() + 1 days;

        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        henriable.actionAdminExtendRiderPayingForInvestment(INVESTMENT_ID, newPayinDate, 0);
    }

    function test_ActionAdminExtendRiderPayingForInvestment_Reverts_WhenInvestmentNotHired() public {
        bytes32 unfundedInvestmentId = bytes32("inv-0002");
        henriable.actionAdminAddInvestment(unfundedInvestmentId, ASSET_ID, 50 * USDC_UNIT, 60, 10 * USDC_UNIT);

        vm.expectRevert(abi.encodeWithSelector(HInvestmentNotHired.selector, unfundedInvestmentId));
        henriable.actionAdminExtendRiderPayingForInvestment(unfundedInvestmentId, block.timestamp + 1 days, 0);
    }

    function test_ActionAdminExtendRiderPayingForInvestment_Reverts_WhenNewDateNotLater() public {
        uint256 currentPayinDate = _nextPayinDate();

        vm.expectRevert(
            abi.encodeWithSelector(
                HInvestmentInvalidRiderNextPayinDate.selector, currentPayinDate, currentPayinDate
            )
        );
        henriable.actionAdminExtendRiderPayingForInvestment(INVESTMENT_ID, currentPayinDate, 0);
    }

    function test_ActionAdminExtendRiderPayingForInvestment_Reverts_WhenNewDateEarlier() public {
        uint256 currentPayinDate = _nextPayinDate();
        uint256 earlierPayinDate = currentPayinDate - 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                HInvestmentInvalidRiderNextPayinDate.selector, earlierPayinDate, currentPayinDate
            )
        );
        henriable.actionAdminExtendRiderPayingForInvestment(INVESTMENT_ID, earlierPayinDate, 0);
    }

    //</editor-fold desc="Reverts">

    //<editor-fold desc="Slash">

    function test_ActionAdminExtendRiderPayingForInvestment_SlashesSavings_WhenSlashRequested() public {
        _makeRiderPayin();
        uint256 newPayinDate = _nextPayinDate() + 1 days;

        henriable.actionAdminExtendRiderPayingForInvestment(INVESTMENT_ID, newPayinDate, 1 * USDC_UNIT);

        // The slash reduces the refundable savings and is tracked in its own structures.
        assertEq(henriable.getInvestmentRiderSavings(0).totalAmountSaved, 1 * USDC_UNIT);
        assertEq(henriable.getStats().totalRiderSavingsSlashedUsd, 1 * USDC_UNIT);
        assertEq(henriable.getRiderSavingsSlashesCount(), 1);
        assertEq(henriable.getRiderSavingsSlashes().length, 1);

        HRiderSavingsSlash memory slash = henriable.getRiderSavingsSlashAt(0);
        assertEq(slash.investmentId, INVESTMENT_ID);
        assertEq(slash.riderAddress, RIDER);
        assertEq(slash.amountSlashed, 1 * USDC_UNIT);

        assertEq(henriable.getRiderSavingsSlashIndex(INVESTMENT_ID), 1);
        assertEq(henriable.getInvestmentRiderSavingsSlashes(INVESTMENT_ID).length, 1);

        assertEq(henriable.getInvestmentRiderSavingsSlashesHistory(0).totalAmountSlashed, 1 * USDC_UNIT);
        assertEq(henriable.getInvestmentRiderSavingsSlashesHistory(0).totalNumberOfTimesSlashed, 1);

        // The extended date is still applied.
        assertEq(_nextPayinDate(), newPayinDate);
    }

    function test_ActionAdminExtendRiderPayingForInvestment_TagsSlashPayouts_AsRiderSavingsSlash() public {
        _makeRiderPayin();

        uint256 ownerPayoutsBefore = henriable.getOwnerPayoutsCount();
        uint256 investorPayoutsBefore = henriable.getInvestorPayoutsCount();

        henriable.actionAdminExtendRiderPayingForInvestment(INVESTMENT_ID, _nextPayinDate() + 1 days, 1 * USDC_UNIT);

        // The slash pays out through the normal payout lists, tagged by type.
        assertEq(henriable.getOwnerPayoutsCount(), ownerPayoutsBefore + 1);
        HOwnerPayout memory ownerPayout = henriable.getOwnerPayoutAt(ownerPayoutsBefore);
        assertEq(uint256(ownerPayout.payoutType), uint256(HPayoutType.RiderSavingsSlash));
        assertEq(ownerPayout.amountPaid, 50_000);

        assertEq(henriable.getInvestorPayoutsCount(), investorPayoutsBefore + 2);
        HInvestorPayout memory seniorPayout = henriable.getInvestorPayoutAt(investorPayoutsBefore);
        assertEq(uint256(seniorPayout.payoutType), uint256(HPayoutType.RiderSavingsSlash));
        assertEq(seniorPayout.amountPaid, 700_000);

        HInvestorPayout memory juniorPayout = henriable.getInvestorPayoutAt(investorPayoutsBefore + 1);
        assertEq(uint256(juniorPayout.payoutType), uint256(HPayoutType.RiderSavingsSlash));
        assertEq(juniorPayout.amountPaid, 250_000);
    }

    function test_ActionAdminExtendRiderPayingForInvestment_PaysSlashToInvestorsAndOwner() public {
        _makeRiderPayin();

        uint256 seniorBalanceBefore = usdc.balanceOf(SENIOR);
        uint256 juniorBalanceBefore = usdc.balanceOf(JUNIOR);
        uint256 ownerBalanceBefore = usdc.balanceOf(address(this));

        henriable.actionAdminExtendRiderPayingForInvestment(INVESTMENT_ID, _nextPayinDate() + 1 days, 1 * USDC_UNIT);

        assertEq(usdc.balanceOf(SENIOR) - seniorBalanceBefore, 700_000);
        assertEq(usdc.balanceOf(JUNIOR) - juniorBalanceBefore, 250_000);
        assertEq(usdc.balanceOf(address(this)) - ownerBalanceBefore, 50_000);
    }

    function test_ActionAdminExtendRiderPayingForInvestment_ExtendsWithoutSlash_WhenSlashIsZero() public {
        _makeRiderPayin();
        uint256 newPayinDate = _nextPayinDate() + 1 days;

        henriable.actionAdminExtendRiderPayingForInvestment(INVESTMENT_ID, newPayinDate, 0);

        assertEq(henriable.getInvestmentRiderSavings(0).totalAmountSaved, 2 * USDC_UNIT);
        assertEq(henriable.getStats().totalRiderSavingsSlashedUsd, 0);
        assertEq(henriable.getRiderSavingsSlashesCount(), 0);
        assertEq(_nextPayinDate(), newPayinDate);
    }

    function test_ActionAdminExtendRiderPayingForInvestment_Reverts_WhenSlashExceedsSaved() public {
        _makeRiderPayin();
        uint256 newPayinDate = _nextPayinDate() + 1 days;

        vm.expectRevert(
            abi.encodeWithSelector(HRiderSavingsSlashExceedsSaved.selector, 3 * USDC_UNIT, 2 * USDC_UNIT)
        );
        henriable.actionAdminExtendRiderPayingForInvestment(INVESTMENT_ID, newPayinDate, 3 * USDC_UNIT);

        assertEq(henriable.getRiderSavingsSlashesCount(), 0);
        assertEq(henriable.getInvestmentRiderSavings(0).totalAmountSaved, 2 * USDC_UNIT);
    }

    //</editor-fold desc="Slash">
}
