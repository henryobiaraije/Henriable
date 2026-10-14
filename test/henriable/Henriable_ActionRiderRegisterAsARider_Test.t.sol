// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    HAsset,
    HInvestmentDoesNotExist,
    HInvestmentNotAcceptingRiders,
    HInvestmentType,
    HInvestor,
    HRider,
    HRiderAlreadyRegistered,
    HRiderHirePurchaseRequest,
    HRiderInsufficientInitialBuyin,
    HRiderInvalidAge,
    HRiderInvalidCountry,
    HRiderInvalidName,
    USDC_UNIT
} from "../../src/types/common.sol";
import {Henriable} from "../../src/Henriable.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";

/// @title Tests for {Henriable.actionRiderRegisterAsARider}.
/// @notice Covers registering for a funded investment's open hire round: the rider profile, the
///         global and per-investment hire-request records, and the initial buy-in pulled into the
///         contract. Also covers every reachable revert. Every USD amount is in USDC base units
///         (6 decimals).
contract HenriableActionRiderRegisterAsARiderTest is Test {
    bytes32 internal constant ASSET_ID = bytes32("keke-0001");
    bytes32 internal constant INVESTMENT_ID = bytes32("inv-0001");
    address internal constant SENIOR = address(0xA11CE);
    address internal constant JUNIOR = address(0xB0B);
    address internal constant RIDER = address(0xB1DE);

    uint256 internal constant INITIAL_BUYIN = 50 * USDC_UNIT;

    Henriable internal henriable;
    MockUSDC internal usdc;

    function setUp() public {
        usdc = new MockUSDC();
        henriable = new Henriable(address(this), IERC20(address(usdc)));

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

    function _register() internal {
        vm.prank(RIDER);
        henriable.actionRiderRegisterAsARider(
            bytes32("Rider"), bytes32("NG"), 30, INITIAL_BUYIN, INVESTMENT_ID
        );
    }

    function test_ActionRiderRegisterAsARider_CreatesRiderProfile() public {
        _register();

        assertEq(henriable.getRidersCount(), 1);
        assertEq(henriable.getRiderIndex(RIDER), 1);

        HRider memory rider = henriable.getRider(RIDER);
        assertEq(rider.riderAddress, RIDER);
        assertEq(rider.name, bytes32("Rider"));
        assertEq(rider.country, bytes32("NG"));
        assertEq(rider.age, 30);
    }

    function test_ActionRiderRegisterAsARider_RecordsHireRequest() public {
        _register();

        assertEq(henriable.getHireRequestsCount(), 1);
        HRiderHirePurchaseRequest memory request = henriable.getHireRequestAt(0);
        assertEq(request.riderId, bytes32(uint256(uint160(RIDER))));
        assertEq(request.investmentId, INVESTMENT_ID);
        assertEq(request.timeRequested, block.timestamp);

        assertEq(henriable.getRiderHirePurchaseRequestIndex(INVESTMENT_ID, RIDER), 1);

        bytes32[] memory investmentRequests = henriable.getRidersHirePurchaseRequestsList(0);
        assertEq(investmentRequests.length, 1);
        assertEq(investmentRequests[0], bytes32(uint256(uint160(RIDER))));
    }

    function test_ActionRiderRegisterAsARider_PullsInitialBuyin() public {
        uint256 riderBefore = usdc.balanceOf(RIDER);
        uint256 contractBefore = usdc.balanceOf(address(henriable));

        _register();

        assertEq(riderBefore - usdc.balanceOf(RIDER), INITIAL_BUYIN);
        assertEq(usdc.balanceOf(address(henriable)) - contractBefore, INITIAL_BUYIN);
        assertEq(henriable.getStats().totalRiders, 1);
        assertEq(henriable.getStats().totalHireRequests, 1);
    }

    function test_ActionRiderRegisterAsARider_UpdatesProfile_WhenRiderReRegisters() public {
        _register();

        // A second register is blocked for the same investment; a different investment is fine.
        bytes32 secondId = bytes32("inv-0002");
        henriable.actionAdminAddInvestment(secondId, ASSET_ID, INITIAL_BUYIN, 60, 10 * USDC_UNIT);
        uint256 start = block.timestamp + 10;
        henriable.actionAdminSetNextInvestmentTimes(secondId, start, start + 1 days);
        vm.warp(start + 1);

        _fundAndApprove(SENIOR);
        _fundAndApprove(JUNIOR);
        vm.prank(SENIOR);
        henriable.actionInvest(_investor(), HInvestmentType.Senior, secondId, 100 * USDC_UNIT);
        vm.prank(JUNIOR);
        henriable.actionInvest(_investor(), HInvestmentType.Junior, secondId, 25 * USDC_UNIT);

        uint256 hireStart = block.timestamp + 10;
        henriable.actionSetNextHireRoundTime(secondId, hireStart, hireStart + 1 days);
        vm.warp(hireStart + 1);

        vm.prank(RIDER);
        henriable.actionRiderRegisterAsARider(
            bytes32("Rider2"), bytes32("GH"), 31, INITIAL_BUYIN, secondId
        );

        // The profile is updated in place, not duplicated.
        assertEq(henriable.getRidersCount(), 1);
        HRider memory rider = henriable.getRider(RIDER);
        assertEq(rider.name, bytes32("Rider2"));
        assertEq(rider.country, bytes32("GH"));
        assertEq(rider.age, 31);
        assertEq(henriable.getHireRequestsCount(), 2);
    }

    //<editor-fold desc="Reverts">

    function test_ActionRiderRegisterAsARider_Reverts_WhenInvestmentDoesNotExist() public {
        vm.prank(RIDER);
        vm.expectRevert(abi.encodeWithSelector(HInvestmentDoesNotExist.selector, bytes32("missing")));
        henriable.actionRiderRegisterAsARider(bytes32("Rider"), bytes32("NG"), 30, INITIAL_BUYIN, bytes32("missing"));
    }

    function test_ActionRiderRegisterAsARider_Reverts_WhenNotAcceptingRiders() public {
        bytes32 idleId = bytes32("inv-idle");
        henriable.actionAdminAddInvestment(idleId, ASSET_ID, INITIAL_BUYIN, 60, 10 * USDC_UNIT);

        vm.prank(RIDER);
        vm.expectRevert(abi.encodeWithSelector(HInvestmentNotAcceptingRiders.selector, idleId));
        henriable.actionRiderRegisterAsARider(bytes32("Rider"), bytes32("NG"), 30, INITIAL_BUYIN, idleId);
    }

    function test_ActionRiderRegisterAsARider_Reverts_WhenNameMissing() public {
        vm.prank(RIDER);
        vm.expectRevert(HRiderInvalidName.selector);
        henriable.actionRiderRegisterAsARider(bytes32(0), bytes32("NG"), 30, INITIAL_BUYIN, INVESTMENT_ID);
    }

    function test_ActionRiderRegisterAsARider_Reverts_WhenCountryMissing() public {
        vm.prank(RIDER);
        vm.expectRevert(HRiderInvalidCountry.selector);
        henriable.actionRiderRegisterAsARider(bytes32("Rider"), bytes32(0), 30, INITIAL_BUYIN, INVESTMENT_ID);
    }

    function test_ActionRiderRegisterAsARider_Reverts_WhenUnderage() public {
        vm.prank(RIDER);
        vm.expectRevert(abi.encodeWithSelector(HRiderInvalidAge.selector, 17));
        henriable.actionRiderRegisterAsARider(bytes32("Rider"), bytes32("NG"), 17, INITIAL_BUYIN, INVESTMENT_ID);
    }

    function test_ActionRiderRegisterAsARider_Reverts_WhenInitialBuyinInsufficient() public {
        vm.prank(RIDER);
        vm.expectRevert(
            abi.encodeWithSelector(HRiderInsufficientInitialBuyin.selector, INITIAL_BUYIN - 1, INITIAL_BUYIN)
        );
        henriable.actionRiderRegisterAsARider(
            bytes32("Rider"), bytes32("NG"), 30, INITIAL_BUYIN - 1, INVESTMENT_ID
        );
    }

    function test_ActionRiderRegisterAsARider_Reverts_WhenAlreadyRegistered() public {
        _register();

        vm.prank(RIDER);
        vm.expectRevert(abi.encodeWithSelector(HRiderAlreadyRegistered.selector, INVESTMENT_ID, RIDER));
        henriable.actionRiderRegisterAsARider(
            bytes32("Rider"), bytes32("NG"), 30, INITIAL_BUYIN, INVESTMENT_ID
        );
    }

    //</editor-fold desc="Reverts">
}
