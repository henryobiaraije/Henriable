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

/// @title HInvestment
/// @notice The full on-chain record of an investment opportunity.
/// @dev    Solidity structs cannot inherit, so the admin-supplied creation settings
///         and the contract-filled fields are combined into this single struct and
///         demarcated by the editor-folds below.
struct HInvestment {
    //<editor-fold desc="Fields: Admin Supplied">

    /// @notice Unique identifier of this investment slot.
    bytes32 investmentId;

    /// @notice Identifier of the {HAsset} this opportunity invests in.
    bytes32 assetId;

    /// @notice Number of senior investor slots that must be filled.
    uint256 totalSeniorInvestorsNeeded;

    /// @notice Number of junior investor slots that must be filled.
    uint256 totalJuniorInvestorsNeeded;

    /// @notice Initial buy-in a rider must pay to start the hire purchase, in USDC.
    uint256 riderInitialBuyinUsd;

    /// @notice Length of each rider payment period, in minutes.
    uint256 periodicRiderPayingInMinutes;

    /// @notice Minimum amount a rider must pay per period, in USDC.
    uint256 minimumRiderPeriodicPayingsUsd;

    //</editor-fold desc="Fields: Admin Supplied">

    //<editor-fold desc="Fields: Contract Filled">

    /// @notice Whether this opportunity is active.
    /// @dev    May only be changed while no investor has invested in it. Forced
    ///         active when the opportunity is created.
    bool active;

    /// @notice Ordered list of senior investor addresses that have invested.
    address[] seniorInvestorsList;

    /// @notice Maps a senior investor address to its index in {seniorInvestorsList}.
    mapping(address => uint256) seniorInvestors;

    /// @notice Ordered list of junior investor addresses that have invested.
    address[] juniorInvestorsList;

    /// @notice Maps a junior investor address to its index in {juniorInvestorsList}.
    mapping(address => uint256) juniorInvestors;

    /// @notice Timestamp at which the investment finished raising its target.
    uint256 investmentsDoneAt;

    /// @notice Current lifecycle state of the investment.
    HInvestmentStatus status;

    // ---------------------------------------------------------------------
    // Scheduling
    // ---------------------------------------------------------------------

    /// @notice Timestamp at which the next investment round is allowed to start.
    uint256 timeNextInvestmentStart;

    /// @notice Timestamp at which the next investment round ends.
    uint256 timeNextInvestmentEnd;

    /// @notice Timestamp at which the next rider hire-request round starts.
    uint256 timeNextRiderHireRequestStart;

    /// @notice Timestamp at which the next rider hire-request round ends.
    uint256 timeNextRiderHireRequestEnd;

    // ---------------------------------------------------------------------
    // Rider hire purchase
    // ---------------------------------------------------------------------

    /// @notice Indices (into the riders' request list) of hire requests for this investment.
    uint256[] ridersHirePurchaseRequestsList;

    /// @notice Maps a rider address to its index in {ridersHirePurchaseRequestsList}.
    mapping(address => uint256) ridersHirePurchaseRequests;

    /// @notice Address of the rider who has hired (or will hire) this asset.
    address riderWhoHiredIt;

    /// @notice Timestamp at which the rider's next periodic payment is due.
    uint256 riderNextPayinDate;

    /// @notice Aggregate record of the rider's payments toward this investment.
    HPayingHistory riderPayinsHistory;

    /// @notice Record of savings accumulated from the rider's payments (slashable).
    HRiderSavingsHistory riderSavings;

    /// @notice Per-investor payout history for this investment.
    mapping(address => HInvestorPayoutsHistory) investorPayoutHistory;

    /// @notice Aggregate payout history for this investment across all investors.
    HInvestmentPayoutsHistory investmentPayoutHistory;

    /// @notice Payout history for the contract/owner on this investment.
    HOwnerPayoutsHistory contractPayoutHistory;

    /// @notice Token id of the NFT title minted for the asset in this investment.
    uint256 nftTokenId;

    /// @notice Timestamp at which the rider completed all payments.
    uint256 timeRiderCompletedPayments;

    /// @notice Timestamp at which the NFT title was transferred to the rider.
    uint256 timeNftTransferedToRider;

    //</editor-fold desc="Fields: Contract Filled">
}

/// @title HInvestor
/// @notice Profile of an investor participating in the platform.
struct HInvestor {
    /// @notice Wallet address of the investor.
    address investorAddress;

    /// @notice Investor's name.
    bytes32 name;

    /// @notice Investor's country.
    bytes32 country;

    /// @notice Investor's age in years; must be at least 18.
    uint8 age;
}

/// @title HRider
/// @notice Profile of a rider who acquires an asset through hire purchase.
struct HRider {
    /// @notice Wallet address of the rider.
    address riderAddress;

    /// @notice Rider's name.
    bytes32 name;

    /// @notice Rider's country.
    bytes32 country;

    /// @notice Rider's age in years; must be at least 18.
    uint8 age;
}

/// @title HRiderHirePurchaseRequest
/// @notice A rider's request to hire the asset backing a given investment.
struct HRiderHirePurchaseRequest {
    /// @notice Identifier of the investment the rider is requesting.
    bytes32 investmentId;

    /// @notice Timestamp at which the request was made.
    uint256 timeRequested;
}

/// @title HRiderPayin
/// @notice A single periodic payment made by a rider under a hire purchase.
struct HRiderPayin {
    /// @notice Identifier of the paying rider.
    bytes32 riderId;

    /// @notice Identifier of the investment the payment is for.
    bytes32 investmentId;

    /// @notice Amount paid in this instalment, in USDC.
    uint256 amountPaid;

    /// @notice Timestamp at which the payment was made.
    uint256 timePaid;

    /// @notice Address the payment was transferred into.
    address addressPaidInto;
}

/// @title HPayingHistory
/// @notice Aggregate record of a rider's payments toward one investment.
struct HPayingHistory {
    /// @notice Address of the rider.
    address riderAddress;

    /// @notice Total amount the rider has paid so far, in USDC.
    uint256 totalAmountPaid;

    /// @notice Total number of payments the rider has made.
    uint256 totalNumberOfTimesPaid;

    /// @notice Total amount the rider is required to pay over the hire purchase, in USDC.
    uint256 targetTotalPay;
}

/// @title HOwnerPayout
/// @notice A single payout made to the contract/owner.
struct HOwnerPayout {
    /// @notice Identifier of the investment the payout came from.
    bytes32 investmentId;

    /// @notice Amount paid out, in USDC.
    uint256 amountPaid;

    /// @notice Timestamp at which the payout was made.
    uint256 timePaid;

    /// @notice Address the payout was transferred into.
    address addressPaidInto;
}

/// @title HOwnerPayoutsHistory
/// @notice Aggregate record of payouts made to the contract/owner.
struct HOwnerPayoutsHistory {
    /// @notice Total amount paid out so far, in USDC.
    uint256 totalAmountPaid;

    /// @notice Total number of payouts made.
    uint256 totalNumberOfTimesPaid;
}

/// @title HInvestorPayout
/// @notice A single payout made to an investor.
struct HInvestorPayout {
    /// @notice Identifier of the investment the payout came from.
    bytes32 investmentId;

    /// @notice Amount paid out, in USDC.
    uint256 amountPaid;

    /// @notice Timestamp at which the payout was made.
    uint256 timePaid;

    /// @notice Address the payout was transferred into.
    address addressPaidInto;
}

/// @title HInvestorPayoutsHistory
/// @notice Aggregate record of a single investor's payouts for one investment.
struct HInvestorPayoutsHistory {
    /// @notice Address of the investor.
    address investorAddress;

    /// @notice Identifier of the investment.
    bytes32 investmentId;

    /// @notice Total amount paid to the investor so far, in USDC.
    uint256 totalAmountPaid;

    /// @notice Total number of payouts made to the investor.
    uint256 totalNumberOfTimesPaid;

    /// @notice Total amount the investor is due to receive over time, in USDC.
    uint256 targetTotalPay;
}

/// @title HInvestmentPayoutsHistory
/// @notice Aggregate record of all payouts made on one investment.
struct HInvestmentPayoutsHistory {
    /// @notice Identifier of the investment.
    bytes32 investmentId;

    /// @notice Total amount paid out so far on the investment, in USDC.
    uint256 totalAmountPaid;

    /// @notice Total number of payouts made on the investment.
    uint256 totalNumberOfTimesPaid;

    /// @notice Total amount due to be paid out on the investment, in USDC.
    uint256 targetTotalPay;
}

/// @title HRiderSavingsHistory
/// @notice Record of a rider's savings for one investment.
/// @dev    A portion of every periodic payment is set aside as savings. The savings
///         can be slashed if the rider defaults or pays late, and are refunded in
///         full if the rider stays committed through the end of the hire purchase,
///         giving them capital for repairs and cash once they own the vehicle.
struct HRiderSavingsHistory {
    /// @notice Address of the rider.
    address riderAddress;

    /// @notice Total amount saved so far, in USDC.
    uint256 totalAmountSaved;

    /// @notice Individual savings entries.
    HRiderSavings[] savings;
}

/// @title HRiderSavings
/// @notice A single savings entry made by a rider.
struct HRiderSavings {
    /// @notice Address of the rider.
    address riderAddress;

    /// @notice Amount saved in this entry, in USDC.
    uint256 amountSaved;

    /// @notice Timestamp at which the amount was saved.
    uint256 timeSaved;
}

//</editor-fold desc="Structs">

//<editor-fold desc="Enums">

/// @title HInvestmentType
/// @notice Identifies which investor tier a position belongs to.
enum HInvestmentType {
    /// @notice Senior investor: paid first, with lower risk and lower reward.
    Senior,
    /// @notice Junior investor: paid after senior investors, with higher risk and higher reward.
    Junior
}

/// @title HInvestmentStatus
/// @notice Lifecycle states of an investment opportunity.
enum HInvestmentStatus {
    /// @notice Investment added but investing has not begun.
    Pending,
    /// @notice Investors can currently invest.
    AcceptingInvestments,
    /// @notice All required investors are in place.
    InvestmentDone,
    /// @notice Riders can now request to hire the asset.
    AcceptingRiders,
    /// @notice A rider has been hired and is making periodic payments.
    Hired,
    /// @notice Rider finished paying and the NFT title has been transferred.
    Complete
}


//</editor-fold desc="Enums">

//<editor-fold desc="Errors">

/// @notice Thrown when an asset is registered without a non-zero id.
error HAssetInvalidId();

/// @notice Thrown when registering an asset whose id is already in use.
/// @param id The already-existing asset id.
error HAssetAlreadyExists(bytes32 id);

/// @notice Thrown when an operation references an asset id that is not registered.
/// @param id The unknown asset id.
error HAssetDoesNotExist(bytes32 id);

/// @notice Thrown when an asset's status is changed while one of its investments
///         is no longer pending.
/// @param id The asset id.
error HAssetHasNonPendingInvestments(bytes32 id);

/// @notice Thrown when an asset is registered without a name.
error HAssetInvalidName();

/// @notice Thrown when an asset is registered with a zero cost price.
error HAssetInvalidCostPrice();

/// @notice Thrown when an asset is registered with a zero sell price.
error HAssetInvalidSellPrice();

/// @notice Thrown when an operation references an asset that is not active.
/// @param id The inactive asset id.
error HAssetNotActive(bytes32 id);

/// @notice Thrown when an investment is registered without a non-zero id.
error HInvestmentInvalidId();

/// @notice Thrown when registering an investment whose id is already in use.
/// @param id The already-existing investment id.
error HInvestmentAlreadyExists(bytes32 id);

/// @notice Thrown when an operation references an investment id that is not registered.
/// @param id The unknown investment id.
error HInvestmentDoesNotExist(bytes32 id);

/// @notice Thrown when an investment is registered with zero senior investor slots.
error HInvestmentInvalidSeniorInvestorsNeeded();

/// @notice Thrown when an investment is registered with zero junior investor slots.
error HInvestmentInvalidJuniorInvestorsNeeded();

/// @notice Thrown when an investment is registered with a zero rider initial buy-in.
error HInvestmentInvalidRiderInitialBuyin();

/// @notice Thrown when an investment is registered with a zero periodic rider paying period.
error HInvestmentInvalidPeriodicRiderPayingInMinutes();

/// @notice Thrown when an investment is registered with a zero minimum rider periodic payment.
error HInvestmentInvalidMinimumRiderPeriodicPayings();

/// @notice Thrown when an investment's level-1 settings are not accurate enough to
///         cover the profits promised to senior and junior investors and owner too.
error HInvestmentInvalidSettings();

//</editor-fold desc="Errors">

//<editor-fold desc="Helper Functions">

//</editor-fold desc="Helper Functions">




