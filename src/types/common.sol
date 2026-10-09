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

    /// @notice Total amount the rider would need to pay over the life of the hire purchase, in USDC.
    /// @dev    Must be large enough to cover the asset cost plus the profits
    ///         promised to both the senior and junior investor pools (except the fixed extra charge for rider slashable, refundable, savings).
    uint256 sellPrice;

    /// @notice Buying price contributed by one senior investor, in USDC.
    /// @dev    The senior pool total is this times {totalNumberOfSeniorInvestorsNeeded}.
    uint256 oneSeniorInvestorBuyingPrice;

    /// @notice Profit one senior investor earns over time, in USDC.
    /// @dev    Senior investors are paid first and carry the lowest risk/reward.
    uint256 oneSeniorInvestorProfit;

    /// @notice Buying price contributed by one junior investor, in USDC.
    /// @dev    The junior pool total is this times {totalNumberOfJuniorInvestorsNeeded}.
    uint256 oneJuniorInvestorBuyingPrice;

    /// @notice Profit one junior investor earns over time, in USDC.
    /// @dev    Junior investors are paid after senior investors and carry the
    ///         higher risk/reward.
    uint256 oneJuniorInvestorProfit;

    /// @notice At every paying, this amount is charged extra from the rider and saved for the rider.
    ///         Then on the day of ownership transfer, its refunded to the rider.
    ///         This would help with repairs and reward for their faithfulness through the process.
    ///         If they default, these savings could be slashed as penalty and to fund investor payouts.
    uint256 riderSlashableRepayableExtraCharge;

    /// @notice Profit owner will earn over time.
    uint256 ownerProfit;

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

    /// @notice Indices (into the global rider payins list) of this investment's payments,
    ///         stored as `index + 1`.
    uint256[] riderPayinIndexes;

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
    /// @notice Identifier of the rider making the request.
    /// @dev    The rider's address encoded as bytes32.
    bytes32 riderId;

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

/// @title HSharingBreakdown
/// @notice Split of one rider periodic payment across its beneficiaries.
/// @dev    Returned by the sharing calculator; the caller credits each party.
struct HSharingBreakdown {
    /// @notice Amount credited to the contract owner, in USDC.
    uint256 ownerAmount;

    /// @notice Total amount credited to the senior investor pool, in USDC.
    uint256 seniorInvestorsAmount;

    /// @notice Total amount credited to the junior investor pool, in USDC.
    uint256 juniorInvestorsAmount;

    /// @notice Amount credited to the rider's savings, in USDC.
    uint256 riderSavingsAmount;
}

/// @title HPayingHistory
/// @notice Aggregate record of a rider's payments toward one investment.
/// @dev    The total the rider owes is {HAsset.sellPrice}; this struct only tracks what
///         they have paid so far against it.
struct HPayingHistory {
    /// @notice Address of the rider.
    address riderAddress;

    /// @notice Total amount the rider has paid so far, in USDC.
    uint256 totalAmountPaid;

    /// @notice Total number of payments the rider has made.
    uint256 totalNumberOfTimesPaid;
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

/// @notice Thrown when an asset's pricing settings cannot cover the payouts it promises,
///         i.e. the rider's sell price does not cover the investor principal and profits.
error HAssetInvalidSettings();

/// @notice Thrown when an investment is registered without a non-zero id.
error HInvestmentInvalidId();

/// @notice Thrown when registering an investment whose id is already in use.
/// @param id The already-existing investment id.
error HInvestmentAlreadyExists(bytes32 id);

/// @notice Thrown when an operation references an investment id that is not registered.
/// @param id The unknown investment id.
error HInvestmentDoesNotExist(bytes32 id);

/// @notice Thrown when an investment is registered with a zero rider initial buy-in.
error HInvestmentInvalidRiderInitialBuyin();

/// @notice Thrown when an investment is registered with a zero periodic rider paying period.
error HInvestmentInvalidPeriodicRiderPayingInMinutes();

/// @notice Thrown when an investment is registered with a zero minimum rider periodic payment.
error HInvestmentInvalidMinimumRiderPeriodicPayings();

/// @notice Thrown when an investment's active flag is changed after an investor has joined.
/// @param id The investment id.
error HInvestmentHasInvestors(bytes32 id);

/// @notice Thrown when an investment's level-1 settings are not accurate enough to
///         cover the profits promised to senior and junior investors.
error HInvestmentInvalidSettings();

/// @notice Thrown when times are set on an investment that is no longer Pending.
/// @param id The investment id.
error HInvestmentNotPending(bytes32 id);

/// @notice Thrown when an operation requires an investment that has finished raising
///         funds ({HInvestmentStatus.InvestmentDone}) but it has not.
/// @param id The investment id.
error HInvestmentNotDone(bytes32 id);

/// @notice Thrown when an investment round's start time is not in the future.
/// @param startTime The invalid start timestamp.
error HInvestmentInvalidStartTime(uint256 startTime);

/// @notice Thrown when an investment round's end time is not after its start time.
/// @param startTime The proposed start timestamp.
/// @param endTime The invalid end timestamp.
error HInvestmentInvalidEndTime(uint256 startTime, uint256 endTime);

/// @notice Thrown when investing in an investment that is not active.
/// @param id The investment id.
error HInvestmentNotActive(bytes32 id);

/// @notice Thrown when investing in an investment that is not accepting investments.
/// @param id The investment id.
error HInvestmentNotAccepting(bytes32 id);

/// @notice Thrown when the approved USDC amount does not match the required slot amount.
/// @param provided The approved amount supplied.
/// @param required The required per-slot amount.
error HInvestmentInvalidAmount(uint256 provided, uint256 required);

/// @notice Thrown when investing in a tier whose investor slots are all filled.
/// @param id The investment id.
error HInvestmentNoOpenSlot(bytes32 id);

/// @notice Thrown when an operation references an investor that is not registered.
/// @param investor The unknown investor address.
error HInvestorDoesNotExist(address investor);

/// @notice Thrown when an investor tries to take a second slot in the same tier.
/// @param investmentId The investment id.
/// @param investor The investor address.
error HInvestorAlreadyInvested(bytes32 investmentId, address investor);

/// @notice Thrown when an investor is younger than the required minimum age.
/// @param age The supplied age.
error HInvestorInvalidAge(uint8 age);

/// @notice Thrown when a rider registers for an investment that is not accepting riders.
/// @param id The investment id.
error HInvestmentNotAcceptingRiders(bytes32 id);

/// @notice Thrown when a rider is registered without a name.
error HRiderInvalidName();

/// @notice Thrown when a rider is registered without a country.
error HRiderInvalidCountry();

/// @notice Thrown when a rider is younger than the required minimum age.
/// @param age The supplied age.
error HRiderInvalidAge(uint8 age);

/// @notice Thrown when a rider's approved initial buy-in is below the required amount.
/// @param provided The approved amount supplied.
/// @param required The required initial buy-in.
error HRiderInsufficientInitialBuyin(uint256 provided, uint256 required);

/// @notice Thrown when a rider tries to register twice for the same investment.
/// @param investmentId The investment id.
/// @param rider The rider address.
error HRiderAlreadyRegistered(bytes32 investmentId, address rider);

/// @notice Thrown when an operation references a rider that is not registered.
/// @param rider The unknown rider address.
error HRiderDoesNotExist(address rider);

/// @notice Thrown when a rider pays on an investment whose hire purchase is not running.
/// @param id The investment id.
error HInvestmentNotHired(bytes32 id);

/// @notice Thrown when an address that is not the hired rider tries to pay.
/// @param investmentId The investment id.
/// @param rider The caller address.
error HRiderNotHired(bytes32 investmentId, address rider);

/// @notice Thrown when a rider pays after already completing the required total.
/// @param id The investment id.
error HRiderPaymentsCompleted(bytes32 id);

/// @notice Thrown when ownership is transferred before the rider has completed all payments.
/// @param id The investment id.
error HRiderPaymentsNotCompleted(bytes32 id);

/// @notice Thrown when ownership is transferred for an investment that is already complete.
/// @param id The investment id.
error HInvestmentAlreadyComplete(bytes32 id);

/// @notice Thrown when a rider's approved payment is below the minimum periodic payment.
/// @param provided The approved amount supplied.
/// @param required The required minimum periodic payment.
error HRiderPayinBelowMinimum(uint256 provided, uint256 required);

/// @notice Thrown when a rider pays after the due date ({HInvestment.riderNextPayinDate}).
/// @param id The investment id.
error HRiderPayinLate(bytes32 id);

//</editor-fold desc="Errors">

//<editor-fold desc="Helper Functions">

//</editor-fold desc="Helper Functions">




