// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

//<editor-fold desc="Imports">



import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
HAsset,
HAssetAlreadyExists,
HAssetInvalidCostPrice,
HAssetInvalidId,
HAssetInvalidName,
HAssetInvalidSellPrice
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

    //<editor-fold desc="Action:Admin: Add Assets & Investments">

    /// @notice Adds a new asset that can be invested in.
    /// @dev    Only the contract owner (admin) may call this.
    ///         Validates the asset, forces it active, appends it to {assetsList} and
    ///         records its position in the {assets} index mapping.
    ///         States updated: {assetsList}, {assets}.
    /// @param _asset The asset configuration to register. Its `id` must be unique and
    ///        non-zero, `name` non-empty, and `costPrice`/`sellPrice` non-zero. The
    ///        `active` field is ignored and set to true.
    function actionAdminAddAsset(HAsset calldata _asset) external onlyOwner {
        if (_asset.id == bytes32(0)) revert HAssetInvalidId();
        if (assets[_asset.id] != 0) revert HAssetAlreadyExists(_asset.id);
        if (_asset.name == bytes32(0)) revert HAssetInvalidName();
        if (_asset.costPrice == 0) revert HAssetInvalidCostPrice();
        if (_asset.sellPrice == 0) revert HAssetInvalidSellPrice();

        HAsset memory newAsset = _asset;
        newAsset.active = true;

        assetsList.push(newAsset);
        assets[_asset.id] = assetsList.length;
    }

    //</editor-fold desc="Action:Admin: Add Assets & Investments">
}