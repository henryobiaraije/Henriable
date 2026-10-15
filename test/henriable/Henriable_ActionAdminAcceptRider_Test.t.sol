// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    HAsset,
    HInvestmentNotAcceptingRiders,
    HInvestmentStatus,
    HInvestmentType,
    HInvestor,
    HPayingHistory,
    HRiderDidNotApplyForHire,
    HRiderDoesNotExist,
    USDC_UNIT
} from "../../src/types/common.sol";
import {Henriable} from "../../src/Henriable.sol";
import {HenriableVehicleNFT} from "../../src/HenriableVehicleNFT.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";

/// @title Tests for {Henriable.actionAdminAcceptRider}.
/// @notice Covers choosing the hired rider from the applicant pool: only an owner may call, the
///         hire round must be open, the chosen address must be a registered applicant, and every
///         other applicant has their initial buy-in refunded. The accepted rider's buy-in is
///         credited toward their hire-purchase total and shared with the investor pools and the
///         owner immediately. Accepting also starts the rider's payment clock. Every USD amount
///         is in USDC base units (6 decimals).
contract HenriableActionAdminAcceptRiderTest is Test {
    bytes32 internal constant ASSET_ID = bytes32("keke-0001");
    bytes32 internal constant INVESTMENT_ID = bytes32("inv-0001");
    address internal constant SENIOR = address(0xA11CE);
    address internal constant JUNIOR = address(0xB0B);
    address internal constant RIDER = address(0xB1DE);
    address internal constant OTHER = address(0xC0FFEE);
    address internal constant OWNER_2 = address(0xBEEF);
    address internal constant NON_OWNER = address(0xDEAD);

    uint256 internal constant INITIAL_BUYIN = 50 * USDC_UNIT;
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
        henriable.actionAdminAddInvestment(INVESTMENT_ID, ASSET_ID, INITIAL_BUYIN, 60, 10 * USDC_UNIT);

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
        _fundAndApprove(OTHER);
        _register(RIDER);
        _register(OTHER);
    }

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
            riderSlashableRepayableExtraCharge: 2 * USDC_UNIT,
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

    function _register(address who) internal {
        vm.prank(who);
        henriable.actionRiderRegisterAsARider(
            bytes32("Rider"), bytes32("NG"), 30, INITIAL_BUYIN, INVESTMENT_ID
        );
    }

    function _status() internal view returns (HInvestmentStatus status) {
        (, , , , , , , status) = henriable.getInvestmentCore(0);
    }

    function _nextPayinDate() internal view returns (uint256 nextPayinDate) {
        (, nextPayinDate, , , ) = henriable.getInvestmentRiderInfo(0);
    }

    function test_ActionAdminAcceptRider_HiresRider_AndStartsPaymentClock() public {
        henriable.actionAdminAcceptRider(INVESTMENT_ID, RIDER);

        assertEq(uint256(_status()), uint256(HInvestmentStatus.Hired));
        (address riderWhoHiredIt, , , , ) = henriable.getInvestmentRiderInfo(0);
        assertEq(riderWhoHiredIt, RIDER);
        assertEq(_nextPayinDate(), block.timestamp + PERIOD);
        assertEq(henriable.getStats().investmentsInHire, 1);
    }

    function test_ActionAdminAcceptRider_AllowsOwner2() public {
        henriable.actionAdminSetOwner2(OWNER_2);

        vm.prank(OWNER_2);
        henriable.actionAdminAcceptRider(INVESTMENT_ID, RIDER);

        assertEq(uint256(_status()), uint256(HInvestmentStatus.Hired));
    }

    function test_ActionAdminAcceptRider_RefundsOtherApplicants() public {
        uint256 otherBefore = usdc.balanceOf(OTHER);
        uint256 contractBefore = usdc.balanceOf(address(henriable));

        henriable.actionAdminAcceptRider(INVESTMENT_ID, RIDER);

        // The rejected applicant gets their initial buy-in back, and the accepted rider's
        // buy-in is shared out immediately, so the contract releases both.
        assertEq(usdc.balanceOf(OTHER) - otherBefore, INITIAL_BUYIN);
        assertEq(usdc.balanceOf(address(henriable)), contractBefore - 2 * INITIAL_BUYIN);

        // The rejected applicant is marked rejected, the accepted rider is not.
        bytes32 otherId = bytes32(uint256(uint160(OTHER)));
        assertEq(henriable.getRejectedRiderIndex(otherId, INVESTMENT_ID), 1);

        bytes32 riderId = bytes32(uint256(uint160(RIDER)));
        assertEq(henriable.getRejectedRiderIndex(riderId, INVESTMENT_ID), 0);
    }

    /// @notice The accepted rider's buy-in counts toward their hire-purchase total and is shared
    ///         with the senior pool immediately (senior is paid first while it is owed).
    function test_ActionAdminAcceptRider_SharesAcceptedBuyin_AndCreditsTotal() public {
        uint256 seniorBefore = usdc.balanceOf(SENIOR);
        uint256 ownerBefore = usdc.balanceOf(address(this));

        henriable.actionAdminAcceptRider(INVESTMENT_ID, RIDER);

        // The buy-in is credited toward the rider's total, so their periodic payments cover the
        // rest of the sell price.
        HPayingHistory memory history = henriable.getInvestmentRiderPayinsHistory(0);
        assertEq(history.riderAddress, RIDER);
        assertEq(history.totalAmountPaid, INITIAL_BUYIN);

        // It is shared right away: the senior pool is owed first, so it receives the full buy-in.
        assertEq(usdc.balanceOf(SENIOR) - seniorBefore, INITIAL_BUYIN);
        assertEq(usdc.balanceOf(address(this)) - ownerBefore, 0);
        assertEq(henriable.getInvestorPayoutHistory(INVESTMENT_ID, SENIOR).totalAmountPaid, INITIAL_BUYIN);
        assertEq(henriable.getStats().totalPayinsUsd, INITIAL_BUYIN);
    }

    //<editor-fold desc="Reverts">

    function test_ActionAdminAcceptRider_Reverts_WhenCallerIsNotAnOwner() public {
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        henriable.actionAdminAcceptRider(INVESTMENT_ID, RIDER);
    }

    function test_ActionAdminAcceptRider_Reverts_WhenNotAcceptingRiders() public {
        bytes32 idleId = bytes32("inv-idle");
        henriable.actionAdminAddInvestment(idleId, ASSET_ID, INITIAL_BUYIN, 60, 10 * USDC_UNIT);

        vm.expectRevert(abi.encodeWithSelector(HInvestmentNotAcceptingRiders.selector, idleId));
        henriable.actionAdminAcceptRider(idleId, RIDER);
    }

    function test_ActionAdminAcceptRider_Reverts_WhenRiderDoesNotExist() public {
        address stranger = address(0x1234);

        vm.expectRevert(abi.encodeWithSelector(HRiderDoesNotExist.selector, stranger));
        henriable.actionAdminAcceptRider(INVESTMENT_ID, stranger);
    }

    function test_ActionAdminAcceptRider_Reverts_WhenRiderDidNotApply() public {
        // A rider registered on another investment of the same asset is not an applicant here.
        bytes32 otherInvestmentId = bytes32("inv-0002");
        henriable.actionAdminAddInvestment(otherInvestmentId, ASSET_ID, INITIAL_BUYIN, 60, 10 * USDC_UNIT);
        uint256 start = block.timestamp + 10;
        henriable.actionAdminSetNextInvestmentTimes(otherInvestmentId, start, start + 1 days);
        vm.warp(start + 1);

        _fundAndApprove(SENIOR);
        _fundAndApprove(JUNIOR);
        vm.prank(SENIOR);
        henriable.actionInvest(_investor(), HInvestmentType.Senior, otherInvestmentId, 100 * USDC_UNIT);
        vm.prank(JUNIOR);
        henriable.actionInvest(_investor(), HInvestmentType.Junior, otherInvestmentId, 25 * USDC_UNIT);

        uint256 hireStart = block.timestamp + 10;
        henriable.actionSetNextHireRoundTime(otherInvestmentId, hireStart, hireStart + 1 days);
        vm.warp(hireStart + 1);

        address applicantElsewhere = address(0xE55E);
        _fundAndApprove(applicantElsewhere);
        vm.prank(applicantElsewhere);
        henriable.actionRiderRegisterAsARider(
            bytes32("Rider"), bytes32("NG"), 30, INITIAL_BUYIN, otherInvestmentId
        );

        vm.expectRevert(abi.encodeWithSelector(HRiderDidNotApplyForHire.selector, INVESTMENT_ID, applicantElsewhere));
        henriable.actionAdminAcceptRider(INVESTMENT_ID, applicantElsewhere);
    }

    //</editor-fold desc="Reverts">
}
