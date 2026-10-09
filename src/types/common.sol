// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


//<editor-fold desc="Constants">

//</editor-fold desc="Constants">

//<editor-fold desc="Structs">

/// @title HAsset
/// @notice Defines an asset (e.g. Keke, Car, Bike, Truck) that riders can acquire
///         through hire purchase and that investors can fund.
/// @dev    The struct holds both the physical/economic settings of the asset and
///         the aggregate economics of the investor pools funding it. The admin
///         configures these values, and they are validated (via the asset/opportunity
///         accuracy calculators) to guarantee that the amount riders pay over time
///         covers the profits promised to senior and junior investors.
struct HAsset {
    /// @notice Unique identifier of the asset.
    /// @dev    Used as the primary key for assets and referenced by investments.
    bytes32 id;

    /// @notice Whether the asset is currently active and available for investment.
    /// @dev    May only be toggled off while no investor has invested in any
    ///         investment that uses this asset.
    bool active;

    /// @notice Human-readable name of the asset (e.g. "Keke-0001-2026", "Bike-0001-2026").
    bytes32 name;

    /// @notice Purchase/cost price of the asset, in USDC.
    /// @dev    The amount required to acquire one unit of the asset.
    uint256 costPrice;

    /// @notice Total amount the rider pays over the life of the hire purchase, in USDC.
    /// @dev    Must be large enough to cover the asset cost plus the profits
    ///         promised to both the senior and junior investor pools.
    uint256 sellPrice;

    /// @notice Total senior investment to be raised for one unit of this asset, in USDC.
    /// @dev    Sum of the buying price contributed by all senior investors.
    uint256 seniorInvestorBuyingPrice;

    /// @notice Total profit the senior investor pool earns over time, in USDC.
    /// @dev    Senior investors are paid first and carry the lowest risk/reward.
    uint256 seniorInvestorProfit;

    /// @notice Total junior investment to be raised for one unit of this asset, in USDC.
    /// @dev    Sum of the buying price contributed by all junior investors.
    uint256 juniorInvestorBuyingPrice;

    /// @notice Total profit the junior investor pool earns over time, in USDC.
    /// @dev    Junior investors are paid after senior investors and carry the
    ///         higher risk/reward.
    uint256 juniorInvestorProfit;

    /// @notice Number of senior investor slots required to fund one unit of this asset.
    /// @dev    Used to know when the senior pool is fully funded.
    uint256 totalNumberOfSeniorInvestorsNeeded;

    /// @notice Number of junior investor slots required to fund one unit of this asset.
    /// @dev    Used to know when the junior pool is fully funded.
    uint256 totalNumberOfJuniorInvestorsNeeded;
}

//</editor-fold desc="Structs">

//<editor-fold desc="Enums">

//</editor-fold desc="Enums">

//<editor-fold desc="Errors">

//</editor-fold desc="Errors">

//<editor-fold desc="Helper Functions">

//</editor-fold desc="Helper Functions">




