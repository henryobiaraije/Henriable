// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

//<editor-fold desc="Imports">



import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
HAsset,
HAssetAlreadyExists,
HAssetHasNonPendingInvestments,
HAssetInvalidCostPrice,
HAssetInvalidId,
HAssetInvalidName,
HAssetInvalidSellPrice,
HInvestment,
HInvestmentStatus
} from "./types/common.sol";
import {HHelper} from "./helpers/HHelper.sol";
//</editor-fold desc="Imports">

/// @title The Henriable contract.
/// @author Obiaraije Henry
contract Henriable is HHelper {

    //<editor-fold desc="Constructor">

    /// @notice Deploys Henriable, setting the contract owner and the USDC token.
    /// @param initialOwner The address that will own the contract.
    /// @param ownerUsdToken_ The USDC token used for investments, payouts and payments.
    constructor(address initialOwner, IERC20 ownerUsdToken_)
    HHelper(initialOwner, ownerUsdToken_)
    {}
    //</editor-fold desc="Constructor">

    //<editor-fold desc="Actions">

    //<editor-fold desc="Action:Admin:Asset Add Assets ">

    /// @notice Adds a new asset that can be invested in.
    /// @dev    Only the contract owner (admin) may call this.
    ///         Validates the asset, forces it active, appends it to {assetsList} and
    ///         records its position in the {assets} index mapping.
    ///         States updated: {assetsList}, {assets}.
    /// @param _asset The asset configuration to register. Its `id` must be unique and
    ///        non-zero, `name` non-empty, and `costPrice`/`sellPrice` non-zero. The
    ///        `active` field is ignored and set to true.
    function actionAdminAddAsset(HAsset calldata _asset) external onlyOwner {

        //<editor-fold desc="Verify Parameters">



        // The id is the registry key, so it must be provided.
        bool assetIdMissing = _asset.id == bytes32(0);
        if (assetIdMissing) revert HAssetInvalidId();

        // `assets[_asset.id]` stores `index + 1`, so any non-zero value means this
        // id is already registered.
        bool assetAlreadyExists = assets[_asset.id] != 0;
        if (assetAlreadyExists) revert HAssetAlreadyExists(_asset.id);

        // A human-readable name is required.
        bool assetNameMissing = _asset.name == bytes32(0);
        if (assetNameMissing) revert HAssetInvalidName();

        // The economics must be non-zero so investor/rider payouts can be computed.
        bool costPriceMissing = _asset.costPrice == 0;
        if (costPriceMissing) revert HAssetInvalidCostPrice();

        bool sellPriceMissing = _asset.sellPrice == 0;
        if (sellPriceMissing) revert HAssetInvalidSellPrice();

        //</editor-fold desc="Verify Parameters">

        // Copy the calldata struct into memory so its fields can be overridden.
        HAsset memory newAsset = _asset;

        // A newly added asset always starts active; the admin disables it later.
        newAsset.active = true;

        // Append the asset to the registry list...
        assetsList.push(newAsset);

        // ...and record its position as `index + 1` (length after push), which gives
        // O(1) lookups and lets 0 mean "not registered".
        assets[_asset.id] = assetsList.length;
    }

    //</editor-fold desc="Action:Admin:Asset Add Assets ">

    //<editor-fold desc="Action:Admin:Asset: Change asset status">

    /// @notice Enables or disables an asset.
    /// @dev    Only the contract owner (admin) may call this.
    ///         The asset status may only change while every investment that depends
    ///         on the asset is still {HInvestmentStatus.Pending}; once any such
    ///         investment has moved past Pending, the asset is locked.
    ///         Disabling an asset also disables its still-pending investments.
    ///         Enabling an asset does NOT re-enable those investments.
    ///         States updated: {assetsList}, and {investmentsList} when disabling.
    /// @param _assetId The id of the asset to update.
    /// @param _status The new active status.
    function actionAdminChangeAssetStatus(bytes32 _assetId, bool _status) external onlyOwner {
        // Get the modifiable asset.
        HAsset storage asset = getAssetStorage(_assetId);

        // Indices (into `investmentsList`) of every investment built on this asset.
        uint256[] storage investmentIndexes = assetInvestments[_assetId];

        // The asset may only change status while every dependent investment is still
        // Pending, so build the set of allowed statuses once.
        HInvestmentStatus[] memory allowedStatuses = new HInvestmentStatus[](1);
        allowedStatuses[0] = HInvestmentStatus.Pending;

        // Walk each dependent investment.
        for (uint256 i = 0; i < investmentIndexes.length; i++) {
            HInvestment storage inv = investmentsList[investmentIndexes[i]];

            // The asset may only change status while every dependent investment is
            // still Pending. Once any investment has progressed beyond Pending, the
            // asset is locked and cannot be toggled.
            bool investmentNotPending = !isInvestmentStatus(inv.investmentId, allowedStatuses);
            if (investmentNotPending) {
                revert HAssetHasNonPendingInvestments(_assetId);
            }

            // When disabling the asset, also disable each still-pending investment.
            // Enabling the asset deliberately does NOT re-enable investments.
            bool disablingAsset = !_status;
            if (disablingAsset) {
                inv.active = false;
            }
        }

        // Finally, apply the requested status to the asset itself.
        asset.active = _status;
    }

    //</editor-fold desc="Action:Admin:Asset: Change asset status">

    //</editor-fold desc="Actions">
}