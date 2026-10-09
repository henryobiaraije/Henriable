// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

//<editor-fold desc="Imports">



import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
HAsset,
HAssetDoesNotExist,
HInvestment,
HInvestmentDoesNotExist,
HInvestmentStatus,
HInvestor,
HInvestorDoesNotExist,
HRider,
HRiderDoesNotExist,
HRiderHirePurchaseRequest,
HRiderPayin,
HRiderSavings,
HPayingHistory,
HOwnerPayout,
HOwnerPayoutsHistory,
HInvestorPayout,
HInvestorPayoutsHistory,
HInvestmentPayoutsHistory,
HRiderSavingsHistory,
HSharingBreakdown
} from "../types/common.sol";
//</editor-fold desc="Imports">

/// @title Helper features and modifiers.
/// @author Obiaraije Henry
/// @dev Inherits OpenZeppelin {Ownable} so the launch owner is set at construction.
contract HHelper is Ownable {

    // Provides safeTransfer/safeTransferFrom, which revert on failure.
    using SafeERC20 for IERC20;

    //<editor-fold desc="States">

    //<editor-fold desc="State: Owner">
    /// @notice USDC token used for all investments, payouts and payments.
    IERC20 internal ownerUsdToken;

    /// @notice All owner/contract payouts ever made.
    HOwnerPayout[] internal ownerPayoutsList;

    /// @notice Maps an investment id to the index (in {ownerPayoutsList}) of the
    ///         most recent owner payout for that investment.
    mapping(bytes32 => uint256) internal ownerPayouts;

    /// @notice Maps an investment id to the aggregate owner payout history for it.
    mapping(bytes32 => HOwnerPayoutsHistory) internal ownerPayoutHistory;

    //</editor-fold desc="State: Owner">

    //<editor-fold desc="State: Assets">

    /// @notice All registered assets, in insertion order.
    HAsset[] internal assetsList;

    /// @notice Maps an asset id to its index in {assetsList}, stored as `index + 1`.
    /// @dev    Encoding the position as `index + 1` makes 0 mean "not registered", so
    ///         this single mapping provides an O(1) existence check and lookup.
    mapping(bytes32 => uint256) internal assets;

    //</editor-fold desc="State: Assets">

    //<editor-fold desc="State: Investments">

    /// @notice Maps an asset id to the indices (into {investmentsList}) of the
    ///         investments created for that asset.
    mapping(bytes32 => uint256[]) internal assetInvestments;

    /// @notice All investment opportunities ever created.
    HInvestment[] internal investmentsList;

    /// @notice Maps an investment id to its index in {investmentsList}, stored as
    ///         `index + 1`. Encoding the position as `index + 1` makes 0 mean
    ///         "not registered" for an O(1) existence check and lookup.
    mapping(bytes32 => uint256) internal investments;

    /// @notice All registered investors.
    HInvestor[] internal investorsList;

    /// @notice Indices (into {investmentsList}) of investments whose rider has fully
    ///         paid and that are complete.
    uint256[] internal completedRiderInvestmentList;

    /// @notice Indices (into {investmentsList}) of completed rider investments. This
    ///         list is append-only and is never cleared.
    uint256[] internal investmentsCompleted;

    //</editor-fold desc="State: Investments">

    //<editor-fold desc="State: Investors">

    /// @notice Maps an investor address to its index in {investorsList}, stored as
    ///         `index + 1`, so 0 means "not registered".
    mapping(address => uint256) internal investors;

    /// @notice All investor payouts ever made.
    HInvestorPayout[] internal investorPayoutList;

    /// @notice Maps an investor address and investment id to the index (in
    ///         {investorPayoutList}) of the investor's payout.
    mapping(address => mapping(bytes32 => uint256)) internal investorPayouts;

    //</editor-fold desc="State: Investors">

    //<editor-fold desc="State: Riders">

    /// @notice All registered riders.
    HRider[] internal ridersList;

    /// @notice Maps a rider address to its index in {ridersList}, stored as
    ///         `index + 1`, so 0 means "not registered".
    mapping(address => uint256) internal riders;

    /// @notice All rider hire-purchase requests ever made.
    HRiderHirePurchaseRequest[] internal ridersHirePurchasesRequestsList;

    /// @notice Maps a rider id and investment id to the index (in
    ///         {ridersHirePurchasesRequestsList}) of the rider's hire request.
    mapping(bytes32 => mapping(bytes32 => uint256)) internal ridersHireRequestPurchasesByInvestment;

    /// @notice Maps a rider id and investment id to a non-zero marker when the rider
    ///         was rejected for that investment.
    mapping(bytes32 => mapping(bytes32 => uint256)) internal rejectedRiders;

    /// @notice All rider periodic payments ever made.
    HRiderPayin[] internal riderPayinsList;

    //</editor-fold desc="State: Riders">

    //</editor-fold desc="States">

    //<editor-fold desc="Constructor">

    /// @notice Deploys the helper, setting the contract owner and the USDC token.
    /// @param initialOwner The address that will own the contract.
    /// @param ownerUsdToken_ The USDC token used for investments, payouts and payments.
    constructor(address initialOwner, IERC20 ownerUsdToken_) Ownable(initialOwner) {
        ownerUsdToken = ownerUsdToken_;
    }

    //</editor-fold desc="Constructor">

    //<editor-fold desc="Is...">

    /// @notice Returns whether an investment is currently in any of the given statuses.
    /// @param investmentId The id of the investment.
    /// @param statuses The statuses to test for.
    /// @return True if the investment's current status equals any entry in `statuses`.
    function isInvestmentStatus(bytes32 investmentId, HInvestmentStatus[] memory statuses)
    internal
    view
    returns (bool)
    {
        HInvestmentStatus currentStatus = getInvestmentStorage(investmentId).status;
        for (uint256 i = 0; i < statuses.length; i++) {
            if (currentStatus == statuses[i]) {
                return true;
            }
        }
        return false;
    }

    //</editor-fold desc="Is...">

    //<editor-fold desc="Calculators">

    /// @notice Checks that the level-1 settings of a new investment opportunity are
    ///         consistent with its asset, so the rider's payments can cover the
    ///         profits promised to the senior and junior investor pools.
    /// @dev    Placeholder: always returns true until the real accuracy math is
    ///         implemented and reviewed. The investment parameter is intentionally unused.
    /// @return True when the level-1 settings are accurate.
    function calcInvestmentOpportunityLevel1SettingsAccuracy(HInvestment storage) internal pure returns (bool) {
        return true;
    }

    /// @notice Splits one rider periodic payment across the owner, the senior and
    ///         junior investor pools, and the rider's savings.
    /// @dev    Placeholder: splits the amount into four equal buckets, with the owner
    ///         absorbing any integer-division remainder. Replace with the real formula.
    /// @param amount The rider payment to split, in USDC.
    /// @return The per-bucket breakdown.
    function calcSharingFormula(uint256 amount) internal pure returns (HSharingBreakdown memory) {
        uint256 seniorInvestorsAmount = amount / 4;
        uint256 juniorInvestorsAmount = amount / 4;
        uint256 riderSavingsAmount = amount / 4;
        uint256 ownerAmount = amount - seniorInvestorsAmount - juniorInvestorsAmount - riderSavingsAmount;

        return HSharingBreakdown({
            ownerAmount: ownerAmount,
            seniorInvestorsAmount: seniorInvestorsAmount,
            juniorInvestorsAmount: juniorInvestorsAmount,
            riderSavingsAmount: riderSavingsAmount
        });
    }

    //</editor-fold desc="Calculators">

    //<editor-fold desc="Maybe">

    /// @notice Advances an investment's lifecycle status when its current state and
    ///         timing allow it.
    /// @dev    State machine: this is the sole place that mutates {HInvestment}.status.
    ///         - Pending -> AcceptingInvestments once the admin-set window opens
    ///           (`timeNextInvestmentStart <= now <= timeNextInvestmentEnd`).
    ///         - AcceptingInvestments -> InvestmentDone once the asset's senior and
    ///           junior pools are both filled, recording {HInvestment.investmentsDoneAt}.
    ///         - InvestmentDone -> AcceptingRiders once the admin-set hire window opens
    ///           (`timeNextRiderHireRequestStart <= now <= timeNextRiderHireRequestEnd`).
    ///         It runs lazily on first use (e.g. when an investor or rider calls in), so
    ///         the status catches up. After each status update it returns.
    /// @param investmentId The id of the investment to update.
    function maybeUpdateInvestmentStatus(bytes32 investmentId) internal {
        HInvestment storage investment = getInvestmentStorage(investmentId);

        HInvestmentStatus currentStatus = investment.status;

        if (currentStatus == HInvestmentStatus.Pending) {
            // The round may only open once the admin has set a start time and now is
            // within the [start, end] window.
            bool investmentTimeSet = investment.timeNextInvestmentStart != 0;
            bool withinInvestmentWindow = investmentTimeSet
                && block.timestamp >= investment.timeNextInvestmentStart
                && block.timestamp <= investment.timeNextInvestmentEnd;

            if (withinInvestmentWindow) {
                investment.status = HInvestmentStatus.AcceptingInvestments;
                return;
            }
        }

        if (currentStatus == HInvestmentStatus.AcceptingInvestments) {
            // The round is done once every investor slot the asset requires is filled.
            HAsset storage asset = getAssetStorage(investment.assetId);

            bool seniorPoolFilled = investment.seniorInvestorsList.length == asset.totalNumberOfSeniorInvestorsNeeded;
            bool juniorPoolFilled = investment.juniorInvestorsList.length == asset.totalNumberOfJuniorInvestorsNeeded;
            bool investmentFullyFunded = seniorPoolFilled && juniorPoolFilled;

            if (investmentFullyFunded) {
                investment.status = HInvestmentStatus.InvestmentDone;
                investment.investmentsDoneAt = block.timestamp;
                return;
            }
        }

        if (currentStatus == HInvestmentStatus.InvestmentDone) {
            // The hire round may open once the admin has set a window and now is within it.
            bool hireTimeSet = investment.timeNextRiderHireRequestStart != 0;
            bool withinHireWindow = hireTimeSet
                && block.timestamp >= investment.timeNextRiderHireRequestStart
                && block.timestamp <= investment.timeNextRiderHireRequestEnd;

            if (withinHireWindow) {
                investment.status = HInvestmentStatus.AcceptingRiders;
                return;
            }
        }
    }

    //</editor-fold desc="Maybe">

    //<editor-fold desc="Upserts">

    /// @notice Creates an investor profile for an address, or updates it if it exists.
    /// @param investorAddress The investor's address.
    /// @param investorProfile The profile fields (name, country, age) to store.
    function upsertInvestor(address investorAddress, HInvestor memory investorProfile) internal {
        bool investorExists = investors[investorAddress] != 0;
        if (investorExists) {
            HInvestor storage existingInvestor = getInvestorStorage(investorAddress);
            existingInvestor.name = investorProfile.name;
            existingInvestor.country = investorProfile.country;
            existingInvestor.age = investorProfile.age;
        } else {
            investorProfile.investorAddress = investorAddress;
            investorsList.push(investorProfile);
            investors[investorAddress] = investorsList.length;
        }
    }

    /// @notice Creates a rider profile for an address, or updates it if it exists.
    /// @param riderAddress The rider's address.
    /// @param riderName The rider's name.
    /// @param riderCountry The rider's country.
    /// @param riderAge The rider's age.
    function upsertRider(address riderAddress, bytes32 riderName, bytes32 riderCountry, uint8 riderAge) internal {
        bool riderExists = riders[riderAddress] != 0;
        if (riderExists) {
            HRider storage existingRider = getRiderStorage(riderAddress);
            existingRider.name = riderName;
            existingRider.country = riderCountry;
            existingRider.age = riderAge;
        } else {
            HRider memory newRider =
                            HRider({riderAddress: riderAddress, name: riderName, country: riderCountry, age: riderAge});
            ridersList.push(newRider);
            riders[riderAddress] = ridersList.length;
        }
    }

    //</editor-fold desc="Upserts">

    //<editor-fold desc="Distributions">

    /// @notice Records the accounting for one rider payment split across its beneficiaries.
    /// @dev    Writes all payout/savings state and moves no tokens, so the caller can keep
    ///         the transfer step last (checks-effects-interactions). The owner and each
    ///         investor in a tier share their pool equally; an empty tier or any division
    ///         remainder stays in the contract.
    /// @param investment The investment the payment belongs to (storage reference).
    /// @param investmentId The id of the investment.
    /// @param breakdown The owner/investor/savings split of the payment.
    function recordDistribution(HInvestment storage investment, bytes32 investmentId, HSharingBreakdown memory breakdown)
        internal
    {
        // Owner accounting.
        if (breakdown.ownerAmount != 0) {
            ownerPayoutsList.push(
                HOwnerPayout({
                    investmentId: investmentId,
                    amountPaid: breakdown.ownerAmount,
                    timePaid: block.timestamp,
                    addressPaidInto: owner()
                })
            );
            ownerPayouts[investmentId] = ownerPayoutsList.length;

            HOwnerPayoutsHistory storage ownerHistory = ownerPayoutHistory[investmentId];
            ownerHistory.totalAmountPaid += breakdown.ownerAmount;
            ownerHistory.totalNumberOfTimesPaid += 1;
        }

        // Per-investor accounting for each tier.
        recordTierPayouts(investment, investmentId, investment.seniorInvestorsList, breakdown.seniorInvestorsAmount);
        recordTierPayouts(investment, investmentId, investment.juniorInvestorsList, breakdown.juniorInvestorsAmount);

        // Rider savings (held in the contract, not transferred).
        if (breakdown.riderSavingsAmount != 0) {
            HRiderSavingsHistory storage savings = investment.riderSavings;
            savings.riderAddress = investment.riderWhoHiredIt;
            savings.totalAmountSaved += breakdown.riderSavingsAmount;
            savings.savings.push(
                HRiderSavings({
                    riderAddress: investment.riderWhoHiredIt,
                    amountSaved: breakdown.riderSavingsAmount,
                    timeSaved: block.timestamp
                })
            );
        }

        // Aggregate investment accounting (excludes rider savings).
        HInvestmentPayoutsHistory storage investmentHistory = investment.investmentPayoutHistory;
        investmentHistory.investmentId = investmentId;
        investmentHistory.totalAmountPaid +=
            breakdown.ownerAmount + breakdown.seniorInvestorsAmount + breakdown.juniorInvestorsAmount;
        investmentHistory.totalNumberOfTimesPaid += 1;
    }

    /// @notice Records an equal-share payout for every investor in a tier.
    /// @param investment The investment the payment belongs to (storage reference).
    /// @param investmentId The id of the investment.
    /// @param tierInvestors The tier's investor list.
    /// @param poolAmount The total amount to split across the tier, in USDC.
    function recordTierPayouts(
        HInvestment storage investment,
        bytes32 investmentId,
        address[] storage tierInvestors,
        uint256 poolAmount
    ) internal {
        uint256 investorsCount = tierInvestors.length;
        if (investorsCount == 0 || poolAmount == 0) {
            return;
        }

        uint256 amountPerInvestor = poolAmount / investorsCount;

        for (uint256 i = 0; i < investorsCount; i++) {
            address investor = tierInvestors[i];

            investorPayoutList.push(
                HInvestorPayout({
                    investmentId: investmentId,
                    amountPaid: amountPerInvestor,
                    timePaid: block.timestamp,
                    addressPaidInto: investor
                })
            );
            investorPayouts[investor][investmentId] = investorPayoutList.length;

            HInvestorPayoutsHistory storage investorHistory = investment.investorPayoutHistory[investor];
            investorHistory.investorAddress = investor;
            investorHistory.investmentId = investmentId;
            investorHistory.totalAmountPaid += amountPerInvestor;
            investorHistory.totalNumberOfTimesPaid += 1;
        }
    }

    /// @notice Transfers the owner and investor shares of a recorded distribution.
    /// @dev    Call only after {recordDistribution}: this is the token-moving step.
    /// @param investment The investment the payment belongs to (storage reference).
    /// @param breakdown The owner/investor/savings split of the payment.
    function transferDistribution(HInvestment storage investment, HSharingBreakdown memory breakdown) internal {
        if (breakdown.ownerAmount != 0) {
            ownerUsdToken.safeTransfer(owner(), breakdown.ownerAmount);
        }

        transferTierShares(investment.seniorInvestorsList, breakdown.seniorInvestorsAmount);
        transferTierShares(investment.juniorInvestorsList, breakdown.juniorInvestorsAmount);
    }

    /// @notice Transfers an equal share of a tier's pool to each of its investors.
    /// @param tierInvestors The tier's investor list.
    /// @param poolAmount The total amount to split across the tier, in USDC.
    function transferTierShares(address[] storage tierInvestors, uint256 poolAmount) internal {
        uint256 investorsCount = tierInvestors.length;
        if (investorsCount == 0 || poolAmount == 0) {
            return;
        }

        uint256 amountPerInvestor = poolAmount / investorsCount;

        for (uint256 i = 0; i < investorsCount; i++) {
            ownerUsdToken.safeTransfer(tierInvestors[i], amountPerInvestor);
        }
    }

    //</editor-fold desc="Distributions">

    //<editor-fold desc="Getters">

    // ------------------------- Asset getters -------------------------

    /// @notice Returns the USDC token used by the platform.
    /// @return The {IERC20} owner USDC token.
    function getOwnerUsdToken() external view returns (IERC20) {
        return ownerUsdToken;
    }

    /// @notice Returns the total number of registered assets.
    /// @return The length of {assetsList}.
    function getAssetsCount() external view returns (uint256) {
        return assetsList.length;
    }

    /// @notice Returns the asset registered at an index.
    /// @param index The index into {assetsList}.
    /// @return The {HAsset} at the given index.
    function getAssetAt(uint256 index) external view returns (HAsset memory) {
        return assetsList[index];
    }

    /// @notice Returns an asset's configuration by id.
    /// @param assetId The id of the asset.
    /// @return The {HAsset} for the given id (zero-filled if it does not exist).
    function getAsset(bytes32 assetId) external view returns (HAsset memory) {
        uint256 indexPlusOne = assets[assetId];
        if (indexPlusOne == 0) {
            HAsset memory notFound;
            return notFound;
        }
        return assetsList[indexPlusOne - 1];
    }

    /// @notice Returns whether an asset id is registered.
    /// @param assetId The id of the asset.
    /// @return True if the asset is registered.
    function getAssetExists(bytes32 assetId) external view returns (bool) {
        return assets[assetId] != 0;
    }

    /// @notice Returns a storage reference to a registered asset.
    /// @dev    Hides the `index + 1` bookkeeping so callers can read or write fields
    ///         directly, e.g. `getAssetStorage(id).active = false;`. Reverts if the
    ///         asset is not registered.
    /// @param assetId The id of the asset.
    /// @return A storage reference to the asset.
    function getAssetStorage(bytes32 assetId) internal view returns (HAsset storage) {
        uint256 indexPlusOne = assets[assetId];

        bool assetDoesNotExist = indexPlusOne == 0;
        if (assetDoesNotExist) revert HAssetDoesNotExist(assetId);

        return assetsList[indexPlusOne - 1];
    }

    /// @notice Returns the ids of the investments created for an asset.
    /// @param assetId The id of the asset.
    /// @return An array of investment ids.
    function getAssetInvestmentIds(bytes32 assetId) external view returns (bytes32[] memory) {
        uint256 assetInvestmentsCount = assetInvestments[assetId].length;
        bytes32[] memory investmentIds = new bytes32[](assetInvestmentsCount);
        for (uint256 i = 0; i < assetInvestmentsCount; i++) {
            investmentIds[i] = getAssetInvestmentStorage(assetId, i).investmentId;
        }
        return investmentIds;
    }

    /// @notice Returns a storage reference to an investment created for an asset.
    /// @dev    Hides the `index + 1` bookkeeping used by {assetInvestments}.
    /// @param assetId The id of the asset.
    /// @param position The position in the asset's investment list.
    /// @return A storage reference to the investment.
    function getAssetInvestmentStorage(bytes32 assetId, uint256 position) internal view returns (HInvestment storage) {
        uint256 indexPlusOne = assetInvestments[assetId][position];
        return investmentsList[indexPlusOne - 1];
    }

    /// @notice Returns the number of investments created for an asset.
    /// @param assetId The id of the asset.
    /// @return The count of investments for the asset.
    function getAssetInvestmentsCount(bytes32 assetId) external view returns (uint256) {
        return assetInvestments[assetId].length;
    }

    // ----------------------- Investment getters ----------------------

    /// @notice Returns the total number of investment opportunities.
    /// @return The length of {investmentsList}.
    function getInvestmentsCount() external view returns (uint256) {
        return investmentsList.length;
    }

    /// @notice Returns the 1-based index in {investmentsList} for an investment id.
    /// @dev    Positions are 1-based (0 means "not registered"); to index the array
    ///         directly, callers subtract 1.
    /// @param investmentId The id of the investment.
    /// @return The 1-based index, or 0 if the investment is not registered.
    function getInvestmentIndex(bytes32 investmentId) external view returns (uint256) {
        return investments[investmentId];
    }

    /// @notice Returns a storage reference to a registered investment.
    /// @dev    Hides the `index + 1` bookkeeping so callers can read or write fields
    ///         directly, e.g. `getInvestmentStorage(id).active = false;`. Reverts if
    ///         the investment is not registered.
    /// @param investmentId The id of the investment.
    /// @return A storage reference to the investment.
    function getInvestmentStorage(bytes32 investmentId) internal view returns (HInvestment storage) {
        uint256 indexPlusOne = investments[investmentId];

        bool investmentDoesNotExist = indexPlusOne == 0;
        if (investmentDoesNotExist) revert HInvestmentDoesNotExist(investmentId);

        return investmentsList[indexPlusOne - 1];
    }

    /// @notice Returns the core (half-investment) fields of an investment.
    /// @param index The index into {investmentsList}.
    /// @return investmentId Unique investment id.
    /// @return active Whether the opportunity is active.
    /// @return assetId Asset being invested in.
    /// @return investmentsDoneAt Time the funding target was reached.
    /// @return riderInitialBuyinUsd Initial rider buy-in, in USDC.
    /// @return periodicRiderPayingInMinutes Length of a rider period, in minutes.
    /// @return minimumRiderPeriodicPayingsUsd Minimum rider payment per period, in USDC.
    /// @return status Current lifecycle status.
    function getInvestmentCore(uint256 index)
    external
    view
    returns (
        bytes32 investmentId,
        bool active,
        bytes32 assetId,
        uint256 investmentsDoneAt,
        uint256 riderInitialBuyinUsd,
        uint256 periodicRiderPayingInMinutes,
        uint256 minimumRiderPeriodicPayingsUsd,
        HInvestmentStatus status
    )
    {
        HInvestment storage inv = investmentsList[index];
        investmentId = inv.investmentId;
        active = inv.active;
        assetId = inv.assetId;
        investmentsDoneAt = inv.investmentsDoneAt;
        riderInitialBuyinUsd = inv.riderInitialBuyinUsd;
        periodicRiderPayingInMinutes = inv.periodicRiderPayingInMinutes;
        minimumRiderPeriodicPayingsUsd = inv.minimumRiderPeriodicPayingsUsd;
        status = inv.status;
    }

    /// @notice Returns the scheduling fields of an investment.
    /// @param index The index into {investmentsList}.
    /// @return timeNextInvestmentStart Start of the next investment round.
    /// @return timeNextInvestmentEnd End of the next investment round.
    /// @return timeNextRiderHireRequestStart Start of the next hire-request round.
    /// @return timeNextRiderHireRequestEnd End of the next hire-request round.
    function getInvestmentSchedule(uint256 index)
    external
    view
    returns (
        uint256 timeNextInvestmentStart,
        uint256 timeNextInvestmentEnd,
        uint256 timeNextRiderHireRequestStart,
        uint256 timeNextRiderHireRequestEnd
    )
    {
        HInvestment storage inv = investmentsList[index];
        timeNextInvestmentStart = inv.timeNextInvestmentStart;
        timeNextInvestmentEnd = inv.timeNextInvestmentEnd;
        timeNextRiderHireRequestStart = inv.timeNextRiderHireRequestStart;
        timeNextRiderHireRequestEnd = inv.timeNextRiderHireRequestEnd;
    }

    /// @notice Returns the rider hire-purchase fields of an investment.
    /// @param index The index into {investmentsList}.
    /// @return riderWhoHiredIt Address of the rider who hired the asset.
    /// @return riderNextPayinDate Time the rider's next payment is due.
    /// @return nftTokenId Token id of the NFT title for the asset.
    /// @return timeRiderCompletedPayments Time the rider completed all payments.
    /// @return timeNftTransferedToRider Time the NFT title was transferred to the rider.
    function getInvestmentRiderInfo(uint256 index)
    external
    view
    returns (
        address riderWhoHiredIt,
        uint256 riderNextPayinDate,
        uint256 nftTokenId,
        uint256 timeRiderCompletedPayments,
        uint256 timeNftTransferedToRider
    )
    {
        HInvestment storage inv = investmentsList[index];
        riderWhoHiredIt = inv.riderWhoHiredIt;
        riderNextPayinDate = inv.riderNextPayinDate;
        nftTokenId = inv.nftTokenId;
        timeRiderCompletedPayments = inv.timeRiderCompletedPayments;
        timeNftTransferedToRider = inv.timeNftTransferedToRider;
    }

    /// @notice Returns the list of senior investors for an investment.
    /// @param index The index into {investmentsList}.
    /// @return The senior investor addresses.
    function getSeniorInvestorsList(uint256 index) external view returns (address[] memory) {
        return investmentsList[index].seniorInvestorsList;
    }

    /// @notice Returns the list of junior investors for an investment.
    /// @param index The index into {investmentsList}.
    /// @return The junior investor addresses.
    function getJuniorInvestorsList(uint256 index) external view returns (address[] memory) {
        return investmentsList[index].juniorInvestorsList;
    }

    /// @notice Returns a senior investor's 1-based index within an investment's senior list.
    /// @dev    Positions are 1-based; 0 means the investor is not in the list.
    /// @param investmentId The id of the investment.
    /// @param investor The investor address.
    /// @return The 1-based index, or 0 if not present.
    function getSeniorInvestorIndex(bytes32 investmentId, address investor)
    external
    view
    returns (uint256)
    {
        return getInvestmentStorage(investmentId).seniorInvestors[investor];
    }

    /// @notice Returns a junior investor's 1-based index within an investment's junior list.
    /// @dev    Positions are 1-based; 0 means the investor is not in the list.
    /// @param investmentId The id of the investment.
    /// @param investor The investor address.
    /// @return The 1-based index, or 0 if not present.
    function getJuniorInvestorIndex(bytes32 investmentId, address investor)
    external
    view
    returns (uint256)
    {
        return getInvestmentStorage(investmentId).juniorInvestors[investor];
    }

    /// @notice Returns the rider ids of the hire-purchase requests for an investment.
    /// @param index The index into {investmentsList}.
    /// @return An array of rider ids.
    function getRidersHirePurchaseRequestsList(uint256 index)
    external
    view
    returns (bytes32[] memory)
    {
        bytes32 investmentId = investmentsList[index].investmentId;
        uint256 requestsCount = investmentsList[index].ridersHirePurchaseRequestsList.length;
        bytes32[] memory riderIds = new bytes32[](requestsCount);
        for (uint256 i = 0; i < requestsCount; i++) {
            riderIds[i] = getInvestmentHireRequestStorage(investmentId, i).riderId;
        }
        return riderIds;
    }

    /// @notice Returns a storage reference to a hire-purchase request of an investment.
    /// @dev    Hides the `index + 1` bookkeeping used by the investment's request list.
    /// @param investmentId The id of the investment.
    /// @param position The position in the investment's hire-request list.
    /// @return A storage reference to the hire-purchase request.
    function getInvestmentHireRequestStorage(bytes32 investmentId, uint256 position)
    internal
    view
    returns (HRiderHirePurchaseRequest storage)
    {
        uint256 indexPlusOne = getInvestmentStorage(investmentId).ridersHirePurchaseRequestsList[position];
        return ridersHirePurchasesRequestsList[indexPlusOne - 1];
    }

    /// @notice Returns a rider's 1-based position in an investment's hire-request list.
    /// @dev    Positions are 1-based; 0 means the rider has no request for the investment.
    /// @param investmentId The id of the investment.
    /// @param rider The rider address.
    /// @return The 1-based position, or 0 if not present.
    function getRiderHirePurchaseRequestIndex(bytes32 investmentId, address rider)
    external
    view
    returns (uint256)
    {
        return getInvestmentStorage(investmentId).ridersHirePurchaseRequests[rider];
    }

    /// @notice Returns the rider payment history of an investment.
    /// @param index The index into {investmentsList}.
    /// @return The {HPayingHistory} for the investment's rider.
    function getInvestmentRiderPayinsHistory(uint256 index)
    external
    view
    returns (HPayingHistory memory)
    {
        return investmentsList[index].riderPayinsHistory;
    }

    /// @notice Returns the rider savings record of an investment.
    /// @param index The index into {investmentsList}.
    /// @return The {HRiderSavingsHistory} for the investment's rider.
    function getInvestmentRiderSavings(uint256 index)
    external
    view
    returns (HRiderSavingsHistory memory)
    {
        return investmentsList[index].riderSavings;
    }

    /// @notice Returns one investor's payout history for an investment.
    /// @param investmentId The id of the investment.
    /// @param investor The investor address.
    /// @return The {HInvestorPayoutsHistory} for that investor.
    function getInvestorPayoutHistory(bytes32 investmentId, address investor)
    external
    view
    returns (HInvestorPayoutsHistory memory)
    {
        return getInvestmentStorage(investmentId).investorPayoutHistory[investor];
    }

    /// @notice Returns the aggregate payout history of an investment.
    /// @param index The index into {investmentsList}.
    /// @return The {HInvestmentPayoutsHistory} for the investment.
    function getInvestmentPayoutHistory(uint256 index)
    external
    view
    returns (HInvestmentPayoutsHistory memory)
    {
        return investmentsList[index].investmentPayoutHistory;
    }

    /// @notice Returns the contract/owner payout history recorded on an investment.
    /// @param index The index into {investmentsList}.
    /// @return The {HOwnerPayoutsHistory} for the investment.
    function getInvestmentContractPayoutHistory(uint256 index)
    external
    view
    returns (HOwnerPayoutsHistory memory)
    {
        return investmentsList[index].contractPayoutHistory;
    }

    // ------------------------ Investor getters -----------------------

    /// @notice Returns the total number of registered investors.
    /// @return The length of {investorsList}.
    function getInvestorsCount() external view returns (uint256) {
        return investorsList.length;
    }

    /// @notice Returns an investor's 1-based index in {investorsList}.
    /// @dev    Positions are 1-based (0 means "not registered"); to index the array
    ///         directly, callers subtract 1.
    /// @param investor The investor address.
    /// @return The 1-based index, or 0 if the investor is not registered.
    function getInvestorIndex(address investor) external view returns (uint256) {
        return investors[investor];
    }

    /// @notice Returns a storage reference to a registered investor.
    /// @dev    Hides the `index + 1` bookkeeping so callers can read or write fields
    ///         directly. Reverts if the investor is not registered.
    /// @param investor The investor address.
    /// @return A storage reference to the investor.
    function getInvestorStorage(address investor) internal view returns (HInvestor storage) {
        uint256 indexPlusOne = investors[investor];

        bool investorDoesNotExist = indexPlusOne == 0;
        if (investorDoesNotExist) revert HInvestorDoesNotExist(investor);

        return investorsList[indexPlusOne - 1];
    }

    /// @notice Returns the investor registered at an index.
    /// @param index The index into {investorsList}.
    /// @return The {HInvestor} at the given index.
    function getInvestorAt(uint256 index) external view returns (HInvestor memory) {
        return investorsList[index];
    }

    /// @notice Returns the investor profile for an address.
    /// @param investor The investor address.
    /// @return The {HInvestor} for the address (zero-filled if not registered).
    function getInvestor(address investor) external view returns (HInvestor memory) {
        uint256 indexPlusOne = investors[investor];

        bool investorDoesNotExist = indexPlusOne == 0;
        if (investorDoesNotExist) {
            HInvestor memory notFound;
            return notFound;
        }

        return investorsList[indexPlusOne - 1];
    }

    // ------------------------- Rider getters -------------------------

    /// @notice Returns the total number of registered riders.
    /// @return The length of {ridersList}.
    function getRidersCount() external view returns (uint256) {
        return ridersList.length;
    }

    /// @notice Returns a rider's 1-based index in {ridersList}.
    /// @dev    Positions are 1-based (0 means "not registered"); to index the array
    ///         directly, callers subtract 1.
    /// @param rider The rider address.
    /// @return The 1-based index, or 0 if the rider is not registered.
    function getRiderIndex(address rider) external view returns (uint256) {
        return riders[rider];
    }

    /// @notice Returns a storage reference to a registered rider.
    /// @dev    Hides the `index + 1` bookkeeping so callers can read or write fields
    ///         directly. Reverts if the rider is not registered.
    /// @param rider The rider address.
    /// @return A storage reference to the rider.
    function getRiderStorage(address rider) internal view returns (HRider storage) {
        uint256 indexPlusOne = riders[rider];

        bool riderDoesNotExist = indexPlusOne == 0;
        if (riderDoesNotExist) revert HRiderDoesNotExist(rider);

        return ridersList[indexPlusOne - 1];
    }

    /// @notice Returns the rider registered at an index.
    /// @param index The index into {ridersList}.
    /// @return The {HRider} at the given index.
    function getRiderAt(uint256 index) external view returns (HRider memory) {
        return ridersList[index];
    }

    /// @notice Returns the rider profile for an address.
    /// @param rider The rider address.
    /// @return The {HRider} for the address (zero-filled if not registered).
    function getRider(address rider) external view returns (HRider memory) {
        uint256 indexPlusOne = riders[rider];

        bool riderDoesNotExist = indexPlusOne == 0;
        if (riderDoesNotExist) {
            HRider memory notFound;
            return notFound;
        }

        return ridersList[indexPlusOne - 1];
    }

    // --------------------- Hire-request getters ----------------------

    /// @notice Returns the total number of rider hire-purchase requests.
    /// @return The length of {ridersHirePurchasesRequestsList}.
    function getHireRequestsCount() external view returns (uint256) {
        return ridersHirePurchasesRequestsList.length;
    }

    /// @notice Returns a rider hire-purchase request at an index.
    /// @param index The index into {ridersHirePurchasesRequestsList}.
    /// @return The {HRiderHirePurchaseRequest} at the given index.
    function getHireRequestAt(uint256 index)
    external
    view
    returns (HRiderHirePurchaseRequest memory)
    {
        return ridersHirePurchasesRequestsList[index];
    }

    /// @notice Returns whether/how a rider was rejected for an investment.
    /// @param riderId The id of the rider.
    /// @param investmentId The id of the investment.
    /// @return A non-zero marker if the rider was rejected, otherwise zero.
    function getRejectedRiderIndex(bytes32 riderId, bytes32 investmentId)
    external
    view
    returns (uint256)
    {
        return rejectedRiders[riderId][investmentId];
    }

    // ----------------------- Rider payin getters ---------------------

    /// @notice Returns the total number of rider payments.
    /// @return The length of {riderPayinsList}.
    function getRiderPayinsCount() external view returns (uint256) {
        return riderPayinsList.length;
    }

    /// @notice Returns a rider payment at an index.
    /// @param index The index into {riderPayinsList}.
    /// @return The {HRiderPayin} at the given index.
    function getRiderPayinAt(uint256 index) external view returns (HRiderPayin memory) {
        return riderPayinsList[index];
    }

    /// @notice Returns the payment indices recorded on an investment.
    /// @param investmentId The id of the investment.
    /// @return The 1-based indices into the global rider payins list.
    function getRiderPayinIndexes(bytes32 investmentId) external view returns (uint256[] memory) {
        return getInvestmentStorage(investmentId).riderPayinIndexes;
    }

    // --------------------- Investor payout getters -------------------

    /// @notice Returns the total number of investor payouts.
    /// @return The length of {investorPayoutList}.
    function getInvestorPayoutsCount() external view returns (uint256) {
        return investorPayoutList.length;
    }

    /// @notice Returns an investor payout at an index.
    /// @param index The index into {investorPayoutList}.
    /// @return The {HInvestorPayout} at the given index.
    function getInvestorPayoutAt(uint256 index) external view returns (HInvestorPayout memory) {
        return investorPayoutList[index];
    }

    /// @notice Returns an investor's payout index for an investment.
    /// @param investor The investor address.
    /// @param investmentId The id of the investment.
    /// @return The index into {investorPayoutList}.
    function getInvestorPayoutIndex(address investor, bytes32 investmentId)
    external
    view
    returns (uint256)
    {
        return investorPayouts[investor][investmentId];
    }

    // ---------------------- Owner payout getters ---------------------

    /// @notice Returns the total number of owner payouts.
    /// @return The length of {ownerPayoutsList}.
    function getOwnerPayoutsCount() external view returns (uint256) {
        return ownerPayoutsList.length;
    }

    /// @notice Returns an owner payout at an index.
    /// @param index The index into {ownerPayoutsList}.
    /// @return The {HOwnerPayout} at the given index.
    function getOwnerPayoutAt(uint256 index) external view returns (HOwnerPayout memory) {
        return ownerPayoutsList[index];
    }

    /// @notice Returns the most recent owner payout index for an investment.
    /// @param investmentId The id of the investment.
    /// @return The index into {ownerPayoutsList}.
    function getOwnerPayoutIndex(bytes32 investmentId) external view returns (uint256) {
        return ownerPayouts[investmentId];
    }

    /// @notice Returns the aggregate owner payout history for an investment.
    /// @param investmentId The id of the investment.
    /// @return The {HOwnerPayoutsHistory} for the investment.
    function getOwnerPayoutHistory(bytes32 investmentId)
    external
    view
    returns (HOwnerPayoutsHistory memory)
    {
        return ownerPayoutHistory[investmentId];
    }

    // ---------------------- Completed getters ------------------------

    /// @notice Returns the number of completed rider investments.
    /// @return The length of {completedRiderInvestmentList}.
    function getCompletedRiderInvestmentsCount() external view returns (uint256) {
        return completedRiderInvestmentList.length;
    }

    /// @notice Returns a completed rider investment index.
    /// @param index The index into {completedRiderInvestmentList}.
    /// @return An index into {investmentsList}.
    function getCompletedRiderInvestmentAt(uint256 index) external view returns (uint256) {
        return completedRiderInvestmentList[index];
    }

    /// @notice Returns the number of investments marked complete.
    /// @return The length of {investmentsCompleted}.
    function getInvestmentsCompletedCount() external view returns (uint256) {
        return investmentsCompleted.length;
    }

    /// @notice Returns a completed investment index.
    /// @param index The index into {investmentsCompleted}.
    /// @return An index into {investmentsList}.
    function getInvestmentsCompletedAt(uint256 index) external view returns (uint256) {
        return investmentsCompleted[index];
    }

    //</editor-fold desc="Getters">
}
