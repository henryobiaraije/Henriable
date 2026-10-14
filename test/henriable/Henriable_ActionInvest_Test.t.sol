// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    HAsset,
    HInvestor,
    HInvestmentStatus,
    HInvestmentType,
    USDC_UNIT
} from "../../src/types/common.sol";
import {Henriable} from "../../src/Henriable.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";

contract HenriableActionInvestTest is Test {
    bytes32 internal constant ASSET_ID = bytes32("keke-0001");
    bytes32 internal constant INVESTMENT_ID = bytes32("inv-0001");
    address internal constant SENIOR = address(0xA11CE);
    address internal constant JUNIOR = address(0xB0B);

    Henriable internal henriable;
    MockUSDC internal usdc;

    function setUp() public {
        usdc = new MockUSDC();
        henriable = new Henriable(address(this), IERC20(address(usdc)));

        henriable.actionAdminAddAsset(_validAsset());

        henriable.actionAdminAddInvestment(INVESTMENT_ID, ASSET_ID, 50 * USDC_UNIT, 60, 10 * USDC_UNIT);

        uint256 start = block.timestamp + 10;
        henriable.actionAdminSetNextInvestmentTimes(INVESTMENT_ID, start, start + 1 days);
        vm.warp(start + 1);

        _fund(SENIOR);
        _fund(JUNIOR);
    }

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

    function _fund(address who) internal {
        usdc.mint(who, 1_000 * USDC_UNIT);
        vm.prank(who);
        usdc.approve(address(henriable), type(uint256).max);
    }

    function _investor() internal pure returns (HInvestor memory) {
        return HInvestor({investorAddress: address(0), name: bytes32("A"), country: bytes32("NG"), age: 30});
    }

    function test_ActionInvest_StatusBecomesInvestmentDone_WhenLastJuniorInvests() public {
        vm.prank(SENIOR);
        henriable.actionInvest(_investor(), HInvestmentType.Senior, INVESTMENT_ID, 100 * USDC_UNIT);

        vm.prank(JUNIOR);
        henriable.actionInvest(_investor(), HInvestmentType.Junior, INVESTMENT_ID, 25 * USDC_UNIT);

        (, , , , , , , HInvestmentStatus status) = henriable.getInvestmentCore(0);
        assertEq(uint256(status), uint256(HInvestmentStatus.InvestmentDone));
    }

    function test_ActionInvest_StatusBecomesInvestmentDone_WhenLastSeniorInvests() public {
        vm.prank(JUNIOR);
        henriable.actionInvest(_investor(), HInvestmentType.Junior, INVESTMENT_ID, 25 * USDC_UNIT);

        vm.prank(SENIOR);
        henriable.actionInvest(_investor(), HInvestmentType.Senior, INVESTMENT_ID, 100 * USDC_UNIT);

        (, , , , , , , HInvestmentStatus status) = henriable.getInvestmentCore(0);
        assertEq(uint256(status), uint256(HInvestmentStatus.InvestmentDone));
    }

    function test_ActionInvest_MultiSlot_StatusBecomesInvestmentDone() public {
        bytes32 secondAssetId = bytes32("keke-0002");
        henriable.actionAdminAddAsset(_validAsset5x20(secondAssetId));

        bytes32 secondId = bytes32("inv-0002");
        henriable.actionAdminAddInvestment(secondId, secondAssetId, 50 * USDC_UNIT, 60, 10 * USDC_UNIT);
        uint256 start = block.timestamp + 10;
        henriable.actionAdminSetNextInvestmentTimes(secondId, start, start + 1 days);
        vm.warp(start + 1);

        for (uint256 i = 0; i < 5; i++) {
            address who = vm.addr(0x1000 + i);
            _fund(who);
            vm.prank(who);
            henriable.actionInvest(_investor(), HInvestmentType.Senior, secondId, 100 * USDC_UNIT);
        }

        (, , , , , , , HInvestmentStatus afterSenior) = henriable.getInvestmentCore(1);
        assertEq(uint256(afterSenior), uint256(HInvestmentStatus.AcceptingInvestments));

        for (uint256 i = 0; i < 20; i++) {
            address who = vm.addr(0x2000 + i);
            _fund(who);
            vm.prank(who);
            henriable.actionInvest(_investor(), HInvestmentType.Junior, secondId, 25 * USDC_UNIT);
        }

        (, , , , , , , HInvestmentStatus status) = henriable.getInvestmentCore(1);
        assertEq(uint256(status), uint256(HInvestmentStatus.InvestmentDone));
    }

    function test_ActionInvest_Interleaved3x2_StatusBecomesInvestmentDone() public {
        bytes32 assetId = bytes32("keke-0003");
        bytes32 invId = bytes32("inv-0003");
        HAsset memory a = _validAsset();
        a.id = assetId;
        a.costPrice = 7_000_000;
        a.sellPrice = 10_990_001;
        a.oneSeniorInvestorBuyingPrice = 1_586_667;
        a.oneSeniorInvestorProfit = 465_500;
        a.oneJuniorInvestorBuyingPrice = 1_120_000;
        a.oneJuniorInvestorProfit = 1_157_100;
        a.riderSlashableRepayableExtraCharge = 140_000;
        a.ownerProfit = 279_300;
        a.totalNumberOfSeniorInvestorsNeeded = 3;
        a.totalNumberOfJuniorInvestorsNeeded = 2;
        henriable.actionAdminAddAsset(a);

        henriable.actionAdminAddInvestment(invId, assetId, 3_626_700, 5, 659_400);
        uint256 start = block.timestamp + 10;
        henriable.actionAdminSetNextInvestmentTimes(invId, start, start + 1 days);
        vm.warp(start + 1);

        address[5] memory who = [address(0x3001), address(0x3002), address(0x3003), address(0x3004), address(0x3005)];
        for (uint256 i = 0; i < 5; i++) {
            _fund(who[i]);
        }

        vm.prank(who[0]);
        henriable.actionInvest(_investor(), HInvestmentType.Senior, invId, 1_586_667);
        vm.prank(who[1]);
        henriable.actionInvest(_investor(), HInvestmentType.Junior, invId, 1_120_000);
        vm.prank(who[2]);
        henriable.actionInvest(_investor(), HInvestmentType.Senior, invId, 1_586_667);
        vm.prank(who[3]);
        henriable.actionInvest(_investor(), HInvestmentType.Junior, invId, 1_120_000);

        (, , , , , , , HInvestmentStatus beforeLast) = henriable.getInvestmentCore(1);
        assertEq(uint256(beforeLast), uint256(HInvestmentStatus.AcceptingInvestments));

        vm.prank(who[4]);
        henriable.actionInvest(_investor(), HInvestmentType.Senior, invId, 1_586_667);

        (, , , , , , , HInvestmentStatus doneStatus) = henriable.getInvestmentCore(1);
        assertEq(uint256(doneStatus), uint256(HInvestmentStatus.InvestmentDone));
    }

    function _validAsset5x20(bytes32 assetId) internal pure returns (HAsset memory asset) {
        asset = _validAsset();
        asset.id = assetId;
        asset.costPrice = 1_000 * USDC_UNIT;
        asset.sellPrice = 1_200 * USDC_UNIT;
        asset.totalNumberOfSeniorInvestorsNeeded = 5;
        asset.totalNumberOfJuniorInvestorsNeeded = 20;
    }
}
