// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    HAsset,
    HAssetAlreadyExists,
    HAssetInvalidCostPrice,
    HAssetInvalidId,
    HAssetInvalidName,
    HAssetInvalidSellPrice,
    HAssetInvalidSettings,
    USDC_UNIT
} from "../../src/types/common.sol";
import {Henriable} from "../../src/Henriable.sol";
import {HenriableVehicleNFT} from "../../src/HenriableVehicleNFT.sol";

/// @title Tests for {Henriable.actionAdminAddAsset}.
/// @notice Covers the asset-adding process: only an owner may add, the id must be unique
///         and non-zero, the name/economics must be non-zero, the pricing settings must be
///         correct, and a valid asset is appended to the registry, indexed, and forced
///         active. Every USD amount is in USDC base units (6 decimals), written as
///         `<dollars> * USDC_UNIT`.
contract HenriableActionAdminAddAssetTest is Test {
    bytes32 internal constant ASSET_ID = bytes32("keke-0001");
    bytes32 internal constant SECOND_ASSET_ID = bytes32("keke-0002");
    address internal constant NON_OWNER = address(0xDEAD);
    address internal constant OWNER_2 = address(0xBEEF);

    Henriable internal henriable;
    HenriableVehicleNFT internal vehicleNft;

    function setUp() public {
        // The test contract is owner1; no USDC is needed to register an asset.
        vehicleNft = new HenriableVehicleNFT(address(this));
        henriable = new Henriable(address(this), IERC20(address(0)), vehicleNft);
        vehicleNft.setMinter(address(henriable));
    }

    /// @notice Builds a correct Keke asset from the worked example: a $1,000 cost price
    ///         covered by $500 of senior buying and $500 of junior buying, $125 of total
    ///         investor profit and $75 of owner profit, so the minimum sell price is $1,200.
    /// @dev    The `active` field is left false so tests can prove it is ignored and forced.
    function validAsset() internal pure returns (HAsset memory asset) {
        asset = HAsset({
            id: ASSET_ID,
            active: false,
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
            totalNumberOfSeniorInvestorsNeeded: 5,
            totalNumberOfJuniorInvestorsNeeded: 20
        });
    }

    //<editor-fold desc="Happy path">

    function test_ActionAdminAddAsset_RegistersAsset_WhenValid() public {
        henriable.actionAdminAddAsset(validAsset());

        assertEq(henriable.getAssetsCount(), 1);
        assertTrue(henriable.getAssetExists(ASSET_ID));
        assertEq(henriable.getAsset(ASSET_ID).id, ASSET_ID);
    }

    function test_ActionAdminAddAsset_StoresConfiguredFields() public {
        HAsset memory asset = validAsset();
        henriable.actionAdminAddAsset(asset);

        HAsset memory stored = henriable.getAsset(ASSET_ID);
        assertEq(stored.id, asset.id);
        assertEq(stored.name, asset.name);
        assertEq(stored.costPrice, asset.costPrice);
        assertEq(stored.sellPrice, asset.sellPrice);
        assertEq(stored.oneSeniorInvestorBuyingPrice, asset.oneSeniorInvestorBuyingPrice);
        assertEq(stored.oneSeniorInvestorProfit, asset.oneSeniorInvestorProfit);
        assertEq(stored.oneJuniorInvestorBuyingPrice, asset.oneJuniorInvestorBuyingPrice);
        assertEq(stored.oneJuniorInvestorProfit, asset.oneJuniorInvestorProfit);
        assertEq(stored.riderSlashableRepayableExtraCharge, asset.riderSlashableRepayableExtraCharge);
        assertEq(stored.ownerProfit, asset.ownerProfit);
        assertEq(stored.sharingPercentSeniorInvestor, asset.sharingPercentSeniorInvestor);
        assertEq(stored.sharingPercentJuniorInvestor, asset.sharingPercentJuniorInvestor);
        assertEq(stored.sharingPercentOwner, asset.sharingPercentOwner);
        assertEq(stored.sharingPercentJuniorInvestorAfterSeniorPaid, asset.sharingPercentJuniorInvestorAfterSeniorPaid);
        assertEq(stored.sharingPercentOwnerAfterSeniorPaid, asset.sharingPercentOwnerAfterSeniorPaid);
        assertEq(stored.totalNumberOfSeniorInvestorsNeeded, asset.totalNumberOfSeniorInvestorsNeeded);
        assertEq(stored.totalNumberOfJuniorInvestorsNeeded, asset.totalNumberOfJuniorInvestorsNeeded);
    }

    function test_ActionAdminAddAsset_ForcesAssetActive_WhenSuppliedInactive() public {
        HAsset memory asset = validAsset();
        asset.active = false;
        henriable.actionAdminAddAsset(asset);

        assertTrue(henriable.getAsset(ASSET_ID).active);
    }

    function test_ActionAdminAddAsset_KeepsAssetActive_WhenSuppliedActive() public {
        HAsset memory asset = validAsset();
        asset.active = true;
        henriable.actionAdminAddAsset(asset);

        assertTrue(henriable.getAsset(ASSET_ID).active);
    }

    function test_ActionAdminAddAsset_CountsAssetAsActiveInStats() public {
        henriable.actionAdminAddAsset(validAsset());

        assertEq(henriable.getStats().totalAssets, 1);
        assertEq(henriable.getStats().activeAssets, 1);
    }

    function test_ActionAdminAddAsset_AppendsAssetsInOrder() public {
        henriable.actionAdminAddAsset(validAsset());

        HAsset memory second = validAsset();
        second.id = SECOND_ASSET_ID;
        second.name = bytes32("Keke-2");
        henriable.actionAdminAddAsset(second);

        assertEq(henriable.getAssetsCount(), 2);
        assertEq(henriable.getAssetAt(0).id, ASSET_ID);
        assertEq(henriable.getAssetAt(1).id, SECOND_ASSET_ID);
        assertEq(henriable.getAsset(ASSET_ID).id, ASSET_ID);
        assertEq(henriable.getAsset(SECOND_ASSET_ID).id, SECOND_ASSET_ID);
    }

    function test_ActionAdminAddAsset_AllowsOwner2() public {
        henriable.actionAdminSetOwner2(OWNER_2);

        vm.prank(OWNER_2);
        henriable.actionAdminAddAsset(validAsset());

        assertTrue(henriable.getAssetExists(ASSET_ID));
    }

    //</editor-fold desc="Happy path">

    //<editor-fold desc="Reverts">

    function test_ActionAdminAddAsset_Reverts_WhenCallerIsNotAnOwner() public {
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        henriable.actionAdminAddAsset(validAsset());

        assertEq(henriable.getAssetsCount(), 0);
    }

    function test_ActionAdminAddAsset_Reverts_WhenIdIsZero() public {
        HAsset memory asset = validAsset();
        asset.id = bytes32(0);

        vm.expectRevert(HAssetInvalidId.selector);
        henriable.actionAdminAddAsset(asset);

        assertEq(henriable.getAssetsCount(), 0);
    }

    function test_ActionAdminAddAsset_Reverts_WhenAssetAlreadyExists() public {
        henriable.actionAdminAddAsset(validAsset());

        vm.expectRevert(abi.encodeWithSelector(HAssetAlreadyExists.selector, ASSET_ID));
        henriable.actionAdminAddAsset(validAsset());

        assertEq(henriable.getAssetsCount(), 1);
    }

    function test_ActionAdminAddAsset_Reverts_WhenNameIsMissing() public {
        HAsset memory asset = validAsset();
        asset.name = bytes32(0);

        vm.expectRevert(HAssetInvalidName.selector);
        henriable.actionAdminAddAsset(asset);

        assertEq(henriable.getAssetsCount(), 0);
    }

    function test_ActionAdminAddAsset_Reverts_WhenCostPriceIsMissing() public {
        HAsset memory asset = validAsset();
        asset.costPrice = 0;

        vm.expectRevert(HAssetInvalidCostPrice.selector);
        henriable.actionAdminAddAsset(asset);

        assertEq(henriable.getAssetsCount(), 0);
    }

    function test_ActionAdminAddAsset_Reverts_WhenSellPriceIsMissing() public {
        HAsset memory asset = validAsset();
        asset.sellPrice = 0;

        vm.expectRevert(HAssetInvalidSellPrice.selector);
        henriable.actionAdminAddAsset(asset);

        assertEq(henriable.getAssetsCount(), 0);
    }

    function test_ActionAdminAddAsset_Reverts_WhenSellPriceBelowPayouts() public {
        HAsset memory asset = validAsset();
        asset.sellPrice = 1_199 * USDC_UNIT;

        vm.expectRevert(HAssetInvalidSettings.selector);
        henriable.actionAdminAddAsset(asset);

        assertEq(henriable.getAssetsCount(), 0);
    }

    function test_ActionAdminAddAsset_Reverts_WhenInvestorBuyingUnderFundsCostPrice() public {
        HAsset memory asset = validAsset();
        asset.costPrice = 2_000 * USDC_UNIT;

        vm.expectRevert(HAssetInvalidSettings.selector);
        henriable.actionAdminAddAsset(asset);

        assertEq(henriable.getAssetsCount(), 0);
    }

    //</editor-fold desc="Reverts">
}
