// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

//<editor-fold desc="Imports">

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    HAsset,
    HAssetAlreadyExists,
    HAssetHasNonPendingInvestments,
    HAssetInvalidCostPrice,
    HAssetInvalidId,
    HAssetInvalidName,
    HAssetInvalidSellPrice,
    HAssetInvalidSettings,
    HAssetNotActive,
    HInvestment,
    HInvestmentAlreadyComplete,
    HInvestmentAlreadyExists,
    HInvestmentAlreadyHasHiredRider,
    HInvestmentHasInvestors,
    HInvestmentInvalidAmount,
    HInvestmentInvalidEndTime,
    HInvestmentInvalidId,
    HInvestmentInvalidMinimumRiderPeriodicPayings,
    HInvestmentInvalidPeriodicRiderPayingInMinutes,
    HInvestmentInvalidRiderInitialBuyin,
    HInvestmentInvalidRiderNextPayinDate,
    HInvestmentRiderInitialBuyinTooHigh,
    HInvestmentInvalidSettings,
    HInvestmentInvalidStartTime,
    HInvestmentNoOpenSlot,
    HInvestmentNotAccepting,
    HInvestmentNotAcceptingRiders,
    HInvestmentNotActive,
    HInvestmentNotDone,
    HInvestmentNotHired,
    HInvestmentNotPending,
    HInvestmentStatus,
    HInvestmentType,
    HInvestor,
    HInvestorInvalidAge,
    HOwner2IsOwner1,
    HPayingHistory,
    HPayoutType,
    HRiderAlreadyRegistered,
    HRiderAlreadyRejectedForHire,
    HRiderDidNotApplyForHire,
    HRiderDoesNotExist,
    HRiderHirePurchaseRequest,
    HRiderInsufficientInitialBuyin,
    HRiderInvalidAge,
    HRiderInvalidCountry,
    HRiderInvalidName,
    HRiderNotHired,
    HRiderPayin,
    HRiderPayinBelowMinimum,
    HRiderPayinLate,
    HRiderPaymentsCompleted,
    HRiderPaymentsNotCompleted,
    HSharingBreakdown,
    HStats
} from "./types/common.sol";
import {HHelper} from "./helpers/HHelper.sol";
import {HenriableVehicleNFT} from "./HenriableVehicleNFT.sol";

//</editor-fold desc="Imports">

/// @title The Henriable contract.
/// @author Obiaraije Henry
/// @dev All USD amounts are expressed as integers in USDC base units (6 decimals), i.e.
///      micro-USDC, where 1 USDC == USDC_UNIT == 10 ** 6 base units (e.g. $14 ==
///      14_000_000 and $0.14 == 140_000). The contract never converts or scales; it moves
///      the raw base-unit value. Callers must therefore pass base units: the frontend uses
///      viem's `parseUnits(x, 6)`, not a whole-dollar number.
contract Henriable is HHelper {
    // Provides safeTransferFrom, which reverts on failure.
    using SafeERC20 for IERC20;

    //<editor-fold desc="Constructor">

    /// @notice Deploys Henriable, setting the contract owner, the USDC token and the NFT.
    /// @param initialOwner The address that will own the contract.
    /// @param ownerUsdToken_ The USDC token used for investments, payouts and payments.
    /// @param vehicleNft_ The vehicle-title NFT collection, whose minter must be set to
    ///        this contract so it can mint and later transfer asset titles.
    constructor(address initialOwner, IERC20 ownerUsdToken_, HenriableVehicleNFT vehicleNft_)
        HHelper(initialOwner, ownerUsdToken_, vehicleNft_)
    {}

    //</editor-fold desc="Constructor">

    //<editor-fold desc="Actions">

    //<editor-fold desc="Action:Admin:Owner: Set owner 2">

    /// @notice Sets the secondary owner, who may run every admin action but not manage owners.
    /// @dev    Only owner1 ({onlyOwner}) may call this, so owner2 cannot set or clear owners.
    ///         Pass address(0) to clear owner2; rejected when `_owner2` is owner1 itself.
    ///         States updated: {owner2}.
    /// @param _owner2 The new secondary owner address, or address(0) to clear it.
    function actionAdminSetOwner2(address _owner2) external onlyOwner {
        bool owner2IsOwner1 = _owner2 == owner();
        if (owner2IsOwner1) revert HOwner2IsOwner1(owner());

        owner2 = _owner2;
    }

    //</editor-fold desc="Action:Admin:Owner: Set owner 2">

    //<editor-fold desc="Action:Admin:Asset Add Assets ">

    /// @notice Adds a new asset that can be invested in.
    /// @dev    Only an owner (admin: owner1 or owner2) may call this.
    ///         Validates the asset, forces it active, appends it to {assetsList} and
    ///         records its position in the {assets} index mapping.
    ///         States updated: {assetsList}, {assets}.
    /// @param _asset The asset configuration to register. Its `id` must be unique and
    ///        non-zero, `name` non-empty, and `costPrice`/`sellPrice` non-zero. The
    ///        `active` field is ignored and set to true.
    function actionAdminAddAsset(HAsset calldata _asset) external onlyOwners {
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

        // The investor pools must fund the asset and the sell price must cover the
        // principal plus the profits promised to both pools, leaving the owner a surplus.
        bool assetSettingsIncorrect = !isAssetSettingsCorrect(_asset);
        if (assetSettingsIncorrect) revert HAssetInvalidSettings();

        //</editor-fold desc="Verify Parameters">

        // Copy the calldata struct into memory; the `active` field is ignored and applied
        // through {setAssetActive} below so the stats counter moves in one place.
        HAsset memory newAsset = _asset;
        newAsset.active = false;

        // Append the asset to the registry list...
        assetsList.push(newAsset);

        // ...and record its position as `index + 1` (length after push), which gives
        // O(1) lookups and lets 0 mean "not registered".
        assets[_asset.id] = assetsList.length;

        // A newly added asset always starts active; the admin disables it later.
        setAssetActive(getAssetStorage(_asset.id), true);
    }

    //</editor-fold desc="Action:Admin:Asset Add Assets ">

    //<editor-fold desc="Action:Admin:Asset: Change asset status">

    /// @notice Enables or disables an asset.
    /// @dev    Only an owner (admin: owner1 or owner2) may call this.
    ///         The asset status may only change while every investment that depends
    ///         on the asset is still {HInvestmentStatus.Pending}; once any such
    ///         investment has moved past Pending, the asset is locked.
    ///         Disabling an asset also disables its still-pending investments.
    ///         Enabling an asset does NOT re-enable those investments.
    ///         States updated: {assetsList}, and {investmentsList} when disabling.
    /// @param _assetId The id of the asset to update.
    /// @param _status The new active status.
    function actionAdminChangeAssetStatus(bytes32 _assetId, bool _status) external onlyOwners {
        // Get the modifiable asset.
        HAsset storage asset = getAssetStorage(_assetId);

        // The asset may only change status while every dependent investment is still
        // Pending, so build the set of allowed statuses once.
        HInvestmentStatus[] memory allowedStatuses = new HInvestmentStatus[](1);
        allowedStatuses[0] = HInvestmentStatus.Pending;

        // Walk each dependent investment.
        uint256 assetInvestmentsCount = assetInvestments[_assetId].length;
        for (uint256 i = 0; i < assetInvestmentsCount; i++) {
            HInvestment storage inv = getAssetInvestmentStorage(_assetId, i);

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
                setInvestmentActive(inv, false);
            }
        }

        // Finally, apply the requested status to the asset itself.
        setAssetActive(asset, _status);
    }

    //</editor-fold desc="Action:Admin:Asset: Change asset status">

    //<editor-fold desc="Action:Admin:Investment: Add investment">

    /// @notice Adds a new investment opportunity against an existing active asset.
    /// @dev    Only an owner (admin: owner1 or owner2) may call this.
    ///         {HInvestment} contains mappings and therefore cannot be passed as a
    ///         calldata parameter, so the admin-supplied settings are taken as
    ///         individual arguments. Validates them, checks the level-1 settings
    ///         against the asset, forces the opportunity active and Pending, appends
    ///         it to {investmentsList}, records its position in the {investments}
    ///         index mapping and links it to its asset via {assetInvestments}.
    ///         States updated: {investmentsList}, {investments}, {assetInvestments}.
    /// @param _investmentId Unique, non-zero id of the new investment slot.
    /// @param _assetId Id of the asset to invest in; must exist and be active.
    /// @param _riderInitialBuyinUsd Initial rider buy-in, in USDC base units (6 decimals);
    ///        must be non-zero. Callers pass base units (frontend: `parseUnits(x, 6)`).
    /// @param _periodicRiderPayingInMinutes Length of a rider period, in minutes; must be non-zero.
    /// @param _minimumRiderPeriodicPayingsUsd Minimum rider payment per period, in USDC base
    ///        units (6 decimals); must be non-zero. Callers pass base units.
    function actionAdminAddInvestment(
        bytes32 _investmentId,
        bytes32 _assetId,
        uint256 _riderInitialBuyinUsd,
        uint256 _periodicRiderPayingInMinutes,
        uint256 _minimumRiderPeriodicPayingsUsd
    ) external onlyOwners {
        //<editor-fold desc="Verify Parameters">

        // The id is the registry key, so it must be provided.
        {
            bool investmentIdMissing = _investmentId == bytes32(0);
            if (investmentIdMissing) revert HInvestmentInvalidId();
        }

        // `investments[_investmentId]` stores `index + 1`, so any non-zero value means
        // this id is already registered.
        {
            bool investmentAlreadyExists = investments[_investmentId] != 0;
            if (investmentAlreadyExists) revert HInvestmentAlreadyExists(_investmentId);
        }

        // The asset must be registered (reverts otherwise via the storage getter)
        // and still active, since a disabled asset cannot raise new investments.
        {
            HAsset storage asset = getAssetStorage(_assetId);

            bool assetNotActive = !asset.active;
            if (assetNotActive) revert HAssetNotActive(_assetId);

            // The buy-in is credited toward the hire-purchase total, so it must leave a
            // balance to pay over the term.
            bool initialBuyinNotBelowSellPrice = _riderInitialBuyinUsd >= asset.sellPrice;
            if (initialBuyinNotBelowSellPrice) {
                revert HInvestmentRiderInitialBuyinTooHigh(_riderInitialBuyinUsd, asset.sellPrice);
            }
        }

        // The rider economics must be non-zero so the hire purchase can start and pay out.
        {
            bool riderInitialBuyinMissing = _riderInitialBuyinUsd == 0;
            if (riderInitialBuyinMissing) revert HInvestmentInvalidRiderInitialBuyin();
        }

        {
            bool periodicRiderPayingInMinutesMissing = _periodicRiderPayingInMinutes == 0;
            if (periodicRiderPayingInMinutesMissing) revert HInvestmentInvalidPeriodicRiderPayingInMinutes();
        }

        {
            bool minimumRiderPeriodicPayingsMissing = _minimumRiderPeriodicPayingsUsd == 0;
            if (minimumRiderPeriodicPayingsMissing) revert HInvestmentInvalidMinimumRiderPeriodicPayings();
        }

        //</editor-fold desc="Verify Parameters">

        // Append the opportunity to the registry list and stage its admin settings
        // so the accuracy calculator can inspect them.
        HInvestment storage newInvestment = investmentsList.push();

        newInvestment.investmentId = _investmentId;
        newInvestment.assetId = _assetId;
        newInvestment.riderInitialBuyinUsd = _riderInitialBuyinUsd;
        newInvestment.periodicRiderPayingInMinutes = _periodicRiderPayingInMinutes;
        newInvestment.minimumRiderPeriodicPayingsUsd = _minimumRiderPeriodicPayingsUsd;

        // Reject a level-1 configuration that cannot cover the profits promised to
        // the senior and junior investor pools. Reverting here discards the staged
        // investment.
        bool level1SettingsInaccurate = !calcInvestmentOpportunityLevel1SettingsAccuracy(newInvestment);
        if (level1SettingsInaccurate) revert HInvestmentInvalidSettings();

        // A newly added opportunity always starts active and Pending; the helpers keep
        // the stats counters in step.
        setInvestmentActive(newInvestment, true);
        setInvestmentStatus(newInvestment, HInvestmentStatus.Pending);

        // ...record its position as `index + 1` (length after push), which gives
        // O(1) lookups and lets 0 mean "not registered"...
        investments[_investmentId] = investmentsList.length;

        // ...and link it to its asset so the asset can enumerate its investments,
        // storing its position as `index + 1` like the id mappings.
        assetInvestments[_assetId].push(investmentsList.length);
    }

    //</editor-fold desc="Action:Admin:Investment: Add investment">

    //<editor-fold desc="Action:Admin:Investment: Change investment status">

    /// @notice Enables or disables an investment opportunity.
    /// @dev    Only an owner (admin: owner1 or owner2) may call this.
    ///         The investment's active flag may only change while no investor has
    ///         joined it; once the senior or junior pool has any investor, the
    ///         opportunity is locked.
    ///         States updated: {investmentsList}.
    /// @param _investmentId The id of the investment to update.
    /// @param _status The new active status.
    function actionAdminChangeInvestmentStatus(bytes32 _investmentId, bool _status) external onlyOwners {
        // Get the modifiable investment (reverts if it is not registered).
        HInvestment storage investment = getInvestmentStorage(_investmentId);

        // The active flag may only change while nobody has invested yet.
        bool investmentHasInvestors =
            investment.seniorInvestorsList.length != 0 || investment.juniorInvestorsList.length != 0;
        if (investmentHasInvestors) revert HInvestmentHasInvestors(_investmentId);

        // Apply the requested status to the investment.
        setInvestmentActive(investment, _status);
    }

    //</editor-fold desc="Action:Admin:Investment: Change investment status">

    //<editor-fold desc="Action:Admin:Investment: Set next investment times">

    /// @notice Sets the start and end of the next investment round for an investment.
    /// @dev    Only an owner (admin: owner1 or owner2) may call this.
    ///         The opportunity must still be Pending or in investment(to extend it) and its asset active, and the
    ///         round must be in the future with `_endTime` after `_startTime`.
    ///         States updated: {investmentsList}.
    /// @param _investmentId The id of the investment to schedule.
    /// @param _startTime Timestamp at which the next investment round starts; must be in the future.
    /// @param _endTime Timestamp at which the next investment round ends; must be after _startTime.
    function actionAdminSetNextInvestmentTimes(bytes32 _investmentId, uint256 _startTime, uint256 _endTime)
        external
        onlyOwners
    {
        // Get the modifiable investment (reverts if it is not registered).
        HInvestment storage investment = getInvestmentStorage(_investmentId);

        // Times may be set while the opportunity is still Pending, or while it is
        // AcceptingInvestments so the admin can extend an open round. The array must
        // be sized for both entries.
        HInvestmentStatus[] memory allowedStatuses = new HInvestmentStatus[](2);
        allowedStatuses[0] = HInvestmentStatus.Pending;
        allowedStatuses[1] = HInvestmentStatus.AcceptingInvestments;

        bool statusNotSettable = !isInvestmentStatus(_investmentId, allowedStatuses);
        if (statusNotSettable) revert HInvestmentNotPending(_investmentId);

        // The backing asset must still be active, i.e. there must be an asset to invest in.
        HAsset storage asset = getAssetStorage(investment.assetId);

        bool assetNotActive = !asset.active;
        if (assetNotActive) revert HAssetNotActive(investment.assetId);

        // The round must start in the future...
        bool startTimeNotInFuture = _startTime <= block.timestamp;
        if (startTimeNotInFuture) revert HInvestmentInvalidStartTime(_startTime);

        // ...and end after it starts.
        bool endTimeNotAfterStartTime = _endTime <= _startTime;
        if (endTimeNotAfterStartTime) revert HInvestmentInvalidEndTime(_startTime, _endTime);

        // Apply the new round window.
        investment.timeNextInvestmentStart = _startTime;
        investment.timeNextInvestmentEnd = _endTime;
    }

    //</editor-fold desc="Action:Admin:Investment: Set next investment times">

    //<editor-fold desc="Action:Admin:Investment: Clear next investment times">

    /// @notice Clears the start and end of the next investment round for an investment.
    /// @dev    Only an owner (admin: owner1 or owner2) may call this.
    ///         The opportunity must still be Pending; both times are reset to 0.
    ///         States updated: {investmentsList}.
    /// @param _investmentId The id of the investment whose round is cleared.
    function actionAdminClearNextInvestmentsTimes(bytes32 _investmentId) external onlyOwners {
        // Get the modifiable investment (reverts if it is not registered).
        HInvestment storage investment = getInvestmentStorage(_investmentId);

        // Times may only be cleared while the opportunity is still Pending.
        HInvestmentStatus[] memory allowedStatuses = new HInvestmentStatus[](1);
        allowedStatuses[0] = HInvestmentStatus.Pending;

        bool investmentNotPending = !isInvestmentStatus(_investmentId, allowedStatuses);
        if (investmentNotPending) revert HInvestmentNotPending(_investmentId);

        // Reset the next investment round window.
        investment.timeNextInvestmentStart = 0;
        investment.timeNextInvestmentEnd = 0;
    }

    //</editor-fold desc="Action:Admin:Investment: Clear next investment times">

    //<editor-fold desc="Action:Investor: Invest">

    /// @notice Lets an address invest into a tier of an active investment opportunity.
    /// @dev    The investor is {msg.sender}; `_investor` only supplies name, country
    ///         and age. The asset defines the per-investor buying price and the number
    ///         of slots, so the required amount is the tier's one-investor buying price.
    ///         The contract pulls exactly that amount from the investor's USDC.
    ///         An address may call this repeatedly and in either tier, taking one seat
    ///         per call, so the same address can appear more than once in a tier's list
    ///         (each entry is a separate seat and is paid its own equal share).
    ///         States updated: {investorsList}, {investors}, and the chosen tier's
    ///         list and mapping inside {investmentsList}.
    /// @param _investor The investor profile (name, country, age) to create or update.
    /// @param _investmentType The tier to invest in (Senior or Junior).
    /// @param _investmentId The id of the investment to invest in.
    /// @param _approvedUSDAmount The USDC amount approved for this slot, in USDC base units
    ///        (6 decimals); must equal the slot amount. Callers pass base units (frontend:
    ///        `parseUnits(x, 6)`).
    function actionInvest(
        HInvestor calldata _investor,
        HInvestmentType _investmentType,
        bytes32 _investmentId,
        uint256 _approvedUSDAmount
    ) external {
        // Let the status helper advance the opportunity if it is due.
        maybeUpdateInvestmentStatus(_investmentId);

        // Get the investment (reverts if it is not registered).
        HInvestment storage investment = getInvestmentStorage(_investmentId);

        // The opportunity must be opening for investments and still active.
        {
            HInvestmentStatus[] memory allowedStatuses = new HInvestmentStatus[](1);
            allowedStatuses[0] = HInvestmentStatus.AcceptingInvestments;

            bool investmentNotAccepting = !isInvestmentStatus(_investmentId, allowedStatuses);
            if (investmentNotAccepting) revert HInvestmentNotAccepting(_investmentId);
        }

        {
            bool investmentNotActive = !investment.active;
            if (investmentNotActive) revert HInvestmentNotActive(_investmentId);
        }

        // The investor must be an adult.
        {
            bool investorTooYoung = _investor.age < 18;
            if (investorTooYoung) revert HInvestorInvalidAge(_investor.age);
        }

        // The asset defines the tier's slots and buying prices.
        HAsset storage asset = getAssetStorage(investment.assetId);

        // Select the tier being invested in.
        mapping(address => uint256) storage theInvestors =
            _investmentType == HInvestmentType.Senior ? investment.seniorInvestors : investment.juniorInvestors;

        address[] storage theInvestorsList =
            _investmentType == HInvestmentType.Senior ? investment.seniorInvestorsList : investment.juniorInvestorsList;

        uint256 theInvestorBuyingPrice = _investmentType == HInvestmentType.Senior
            ? asset.oneSeniorInvestorBuyingPrice
            : asset.oneJuniorInvestorBuyingPrice;

        uint256 theInvestorSlotsNeeded = _investmentType == HInvestmentType.Senior
            ? asset.totalNumberOfSeniorInvestorsNeeded
            : asset.totalNumberOfJuniorInvestorsNeeded;

        // An address may invest any number of times, in either tier, taking one seat per
        // call; the only limit is the tier's remaining slots (checked below).

        // There must still be an open slot (also guards against a zero-slot asset).
        {
            bool noOpenSlot = theInvestorsList.length >= theInvestorSlotsNeeded;
            if (noOpenSlot) revert HInvestmentNoOpenSlot(_investmentId);
        }

        // The approved amount must equal the per-investor amount.
        uint256 requiredAmount = theInvestorBuyingPrice;
        {
            bool amountIncorrect = _approvedUSDAmount != requiredAmount;
            if (amountIncorrect) revert HInvestmentInvalidAmount(_approvedUSDAmount, requiredAmount);
        }

        // Create or update the caller's investor profile.
        upsertInvestor(msg.sender, _investor);

        // Record the slot in the chosen tier.
        theInvestorsList.push(msg.sender);
        theInvestors[msg.sender] = theInvestorsList.length;

        // Keep the platform totals in step: one filled position and the gross buy-in.
        bool seniorInvestment = _investmentType == HInvestmentType.Senior;
        if (seniorInvestment) {
            stats.totalSeniorPositions += 1;
            stats.totalSeniorInvestedUsd += theInvestorBuyingPrice;
        } else {
            stats.totalJuniorPositions += 1;
            stats.totalJuniorInvestedUsd += theInvestorBuyingPrice;
        }

        // Let the status helper react (e.g. mark the opportunity done once full).
        maybeUpdateInvestmentStatus(_investmentId);

        // Pull the USDC (already in base units) from the investor into the contract
        // (reverts on failure). No scaling is applied: requiredAmount is base units.
        ownerUsdToken.safeTransferFrom(msg.sender, address(this), requiredAmount);
    }

    //</editor-fold desc="Action:Investor: Invest">

    //<editor-fold desc="Action:Admin:Investment: Set next hire round time">

    /// @notice Sets the window during which riders may request to hire an investment's asset.
    /// @dev    Only an owner (admin: owner1 or owner2) may call this.
    ///         The opportunity must be funded ({HInvestmentStatus.InvestmentDone}) or, once a
    ///         hire round is open, still accepting riders ({HInvestmentStatus.AcceptingRiders})
    ///         so an in-progress round can be extended. The window must be in the future with
    ///         `_endTime` after `_startTime`.
    ///         States updated: {investmentsList}.
    /// @param _investmentId The id of the investment to schedule.
    /// @param _startTime Timestamp at which the next hire-request round starts; must be in the future.
    /// @param _endTime Timestamp at which the next hire-request round ends; must be after _startTime.
    function actionSetNextHireRoundTime(bytes32 _investmentId, uint256 _startTime, uint256 _endTime)
        external
        onlyOwners
    {
        // Get the modifiable investment (reverts if it is not registered).
        HInvestment storage investment = getInvestmentStorage(_investmentId);

        // Hire times may be set once investing has finished, or while riders are still being
        // accepted so an open hire round can be extended.
        HInvestmentStatus[] memory allowedStatuses = new HInvestmentStatus[](2);
        allowedStatuses[0] = HInvestmentStatus.InvestmentDone;
        allowedStatuses[1] = HInvestmentStatus.AcceptingRiders;

        bool statusNotSettable = !isInvestmentStatus(_investmentId, allowedStatuses);
        if (statusNotSettable) revert HInvestmentNotDone(_investmentId);

        // The round must start in the future...
        bool startTimeNotInFuture = _startTime <= block.timestamp;
        if (startTimeNotInFuture) revert HInvestmentInvalidStartTime(_startTime);

        // ...and end after it starts.
        bool endTimeNotAfterStartTime = _endTime <= _startTime;
        if (endTimeNotAfterStartTime) revert HInvestmentInvalidEndTime(_startTime, _endTime);

        // Apply the new hire-request window.
        investment.timeNextRiderHireRequestStart = _startTime;
        investment.timeNextRiderHireRequestEnd = _endTime;
    }

    //</editor-fold desc="Action:Admin:Investment: Set next hire round time">

    //<editor-fold desc="Action:Admin:Investment: Clear next hire time">

    /// @notice Clears the rider hire-request window for a funded investment.
    /// @dev    Only an owner (admin: owner1 or owner2) may call this.
    ///         The opportunity must be funded ({HInvestmentStatus.InvestmentDone}); both
    ///         hire-request times are reset to 0.
    ///         States updated: {investmentsList}.
    /// @param _investmentId The id of the investment whose hire window is cleared.
    function actionClearNextHireTime(bytes32 _investmentId) external onlyOwners {
        // Get the modifiable investment (reverts if it is not registered).
        HInvestment storage investment = getInvestmentStorage(_investmentId);

        // Hire times may only be cleared once investing has finished.
        HInvestmentStatus[] memory allowedStatuses = new HInvestmentStatus[](2);
        allowedStatuses[0] = HInvestmentStatus.InvestmentDone;
        allowedStatuses[1] = HInvestmentStatus.Pending;

        bool notReadyToSetHireTime = !isInvestmentStatus(_investmentId, allowedStatuses);
        if (notReadyToSetHireTime) revert HInvestmentNotDone(_investmentId);

        // Reset the next hire-request window.
        investment.timeNextRiderHireRequestStart = 0;
        investment.timeNextRiderHireRequestEnd = 0;
    }

    //</editor-fold desc="Action:Admin:Investment: Clear next hire time">

    //<editor-fold desc="Action:Rider: Register as a rider">

    /// @notice Registers the caller as a rider for a funded investment's hire round.
    /// @dev    The rider is {msg.sender}; the initial buy-in is pulled into the contract
    ///         so it can be refunded if the rider is later rejected. Registration is
    ///         only allowed while the investment is {HInvestmentStatus.AcceptingRiders}.
    ///         States updated: {ridersList}, {riders}, {ridersHirePurchasesRequestsList},
    ///         {ridersHireRequestPurchasesByInvestment}, and the investment's
    ///         {HInvestment.ridersHirePurchaseRequestsList}/{ridersHirePurchaseRequests}.
    /// @param _name The rider's name; must be non-zero.
    /// @param _country The rider's country; must be non-zero.
    /// @param _age The rider's age; must be at least 18.
    /// @param _approvedInitialBuyin The USDC the rider approved, in USDC base units (6
    ///        decimals); must cover the required buy-in. Callers pass base units.
    /// @param _investmentId The id of the investment to register for.
    function actionRiderRegisterAsARider(
        bytes32 _name,
        bytes32 _country,
        uint8 _age,
        uint256 _approvedInitialBuyin,
        bytes32 _investmentId
    ) external {
        // Let the status helper advance the opportunity if it is due.
        maybeUpdateInvestmentStatus(_investmentId);

        // Get the investment (reverts if it is not registered).
        HInvestment storage investment = getInvestmentStorage(_investmentId);

        //<editor-fold desc="Verify Params">

        // Registration must be open for the investment.
        {
            HInvestmentStatus[] memory allowedStatuses = new HInvestmentStatus[](1);
            allowedStatuses[0] = HInvestmentStatus.AcceptingRiders;

            bool registrationNotOpen = !isInvestmentStatus(_investmentId, allowedStatuses);
            if (registrationNotOpen) revert HInvestmentNotAcceptingRiders(_investmentId);
        }

        // Validate the rider's profile.
        {
            bool riderNameMissing = _name == bytes32(0);
            if (riderNameMissing) revert HRiderInvalidName();
        }

        {
            bool riderCountryMissing = _country == bytes32(0);
            if (riderCountryMissing) revert HRiderInvalidCountry();
        }

        {
            bool riderTooYoung = _age < 18;
            if (riderTooYoung) revert HRiderInvalidAge(_age);
        }

        // The approved buy-in must cover the required initial buy-in.
        uint256 requiredInitialBuyin = investment.riderInitialBuyinUsd;
        {
            bool initialBuyinInsufficient = _approvedInitialBuyin < requiredInitialBuyin;
            if (initialBuyinInsufficient) {
                revert HRiderInsufficientInitialBuyin(_approvedInitialBuyin, requiredInitialBuyin);
            }
        }

        //</editor-fold desc="Verify Params">

        // A rider may register only once per investment round.
        bytes32 riderId = bytes32(uint256(uint160(msg.sender)));
        {
            bool riderAlreadyRegistered = ridersHireRequestPurchasesByInvestment[riderId][_investmentId] != 0;
            if (riderAlreadyRegistered) revert HRiderAlreadyRegistered(_investmentId, msg.sender);
        }

        // Create or update the rider's profile.
        upsertRider(msg.sender, _name, _country, _age);

        // Record the hire request globally and on the investment.
        HRiderHirePurchaseRequest memory hireRequest =
            HRiderHirePurchaseRequest({riderId: riderId, investmentId: _investmentId, timeRequested: block.timestamp});

        // Record the hire request globally and on the investment. Every stored position
        // is `index + 1` (0 = "not registered"); HHelper getters hide the conversion.
        ridersHirePurchasesRequestsList.push(hireRequest);
        uint256 globalRequestIndexPlusOne = ridersHirePurchasesRequestsList.length;

        // Update investment's higher purchase list.
        investment.ridersHirePurchaseRequestsList.push(globalRequestIndexPlusOne);
        // Get new length of investment's number of hire-purchase sent.
        uint256 investmentRequestIndexPlusOne = investment.ridersHirePurchaseRequestsList.length;
        // Update specific rider's by investment investment hire purchase mapping.
        ridersHireRequestPurchasesByInvestment[riderId][_investmentId] = globalRequestIndexPlusOne;

        // Update investment mapping.
        investment.ridersHirePurchaseRequests[msg.sender] = investmentRequestIndexPlusOne;

        // Pull the initial buy-in into the contract (reverts on failure).
        ownerUsdToken.safeTransferFrom(msg.sender, address(this), requiredInitialBuyin);
    }

    //</editor-fold desc="Action:Rider: Register as a rider">

    //<editor-fold desc="Action:Admin:Rider: Accept rider">

    /// @notice Accepts one applicant as the rider for a funded investment and rejects the rest.
    /// @dev    Only an owner (admin: owner1 or owner2) may call this.
    ///         The investment must still be {HInvestmentStatus.AcceptingRiders} and have no
    ///         hired rider yet; the chosen rider must exist, must have applied for the
    ///         investment (recorded by {actionRiderRegisterAsARider}) and must not have been
    ///         rejected before. Every other applicant is marked rejected via {rejectedRiders}
    ///         and has their initial buy-in refunded. The accepted rider's buy-in is credited
    ///         toward their hire-purchase total and shared with the investor pools and the
    ///         owner immediately. The investment then moves to {HInvestmentStatus.Hired} and
    ///         the rider's next payment date is set one period from now.
    ///         States updated: {HInvestment.riderWhoHiredIt}, {HInvestment.riderNextPayinDate},
    ///         {HInvestment.status}, {rejectedRiders}, {HInvestment.riderPayinsHistory},
    ///         {ownerPayoutsList}, {investorPayoutList} and the payout histories.
    /// @param _investmentId The id of the investment whose rider is being chosen.
    /// @param _riderAddress The applicant to accept as the hired rider.
    function actionAdminAcceptRider(bytes32 _investmentId, address _riderAddress) external onlyOwners {
        // Let the status helper advance the opportunity if it is due.
        maybeUpdateInvestmentStatus(_investmentId);

        //<editor-fold desc="Get the Investment">

        // Get the modifiable investment (reverts if it is not registered).
        HInvestment storage investment = getInvestmentStorage(_investmentId);
        //</editor-fold desc="Get the Investment">

        //<editor-fold desc="Verify Params">

        // The hire round must still be open.
        {
            HInvestmentStatus[] memory allowedStatuses = new HInvestmentStatus[](1);
            allowedStatuses[0] = HInvestmentStatus.AcceptingRiders;

            bool hireRoundNotOpen = !isInvestmentStatus(_investmentId, allowedStatuses);
            if (hireRoundNotOpen) revert HInvestmentNotAcceptingRiders(_investmentId);
        }

        // Only one rider can be accepted per investment.
        {
            bool riderAlreadyHired = investment.riderWhoHiredIt != address(0);
            if (riderAlreadyHired) revert HInvestmentAlreadyHasHiredRider(_investmentId);
        }

        // The accepted address must be a registered rider...
        {
            bool riderDoesNotExist = riders[_riderAddress] == 0;
            if (riderDoesNotExist) revert HRiderDoesNotExist(_riderAddress);
        }

        // ...who actually applied for this investment...
        {
            bytes32 riderId = bytes32(uint256(uint160(_riderAddress)));
            bool riderDidNotApply = ridersHireRequestPurchasesByInvestment[riderId][_investmentId] == 0;
            if (riderDidNotApply) revert HRiderDidNotApplyForHire(_investmentId, _riderAddress);
        }

        // ...and has not already been rejected for it.
        {
            bytes32 riderId = bytes32(uint256(uint160(_riderAddress)));
            bool riderAlreadyRejected = rejectedRiders[riderId][_investmentId] != 0;
            if (riderAlreadyRejected) revert HRiderAlreadyRejectedForHire(_investmentId, _riderAddress);
        }

        //</editor-fold desc="Verify Params">

        //<editor-fold desc="Accept the rider">

        // Record the hired rider and start their payment clock one period from now.
        investment.riderWhoHiredIt = _riderAddress;
        investment.riderNextPayinDate = block.timestamp + (investment.periodicRiderPayingInMinutes * 60);

        //</editor-fold desc="Accept the rider">

        //<editor-fold desc="Reject and refund other applicants">

        // Reject every other applicant and refund the initial buy-in each of them paid.
        // The buy-in is the investment's initial buy-in, which is exactly what
        // {actionRiderRegisterAsARider} pulled in from each applicant.
        uint256 initialBuyin = investment.riderInitialBuyinUsd;
        for (uint256 i = 0; i < investment.ridersHirePurchaseRequestsList.length; i++) {
            address applicant = address(uint160(uint256(getInvestmentHireRequestStorage(_investmentId, i).riderId)));

            bool isAcceptedRider = applicant == _riderAddress;
            if (isAcceptedRider) {
                continue;
            }

            // Skip anyone already rejected so a rejection and its refund happen at most once.
            bytes32 applicantId = bytes32(uint256(uint160(applicant)));
            bool applicantAlreadyRejected = rejectedRiders[applicantId][_investmentId] != 0;
            if (applicantAlreadyRejected) {
                continue;
            }

            // Effects: mark rejected before moving any token.
            rejectedRiders[applicantId][_investmentId] = 1;

            // Interactions: refund this applicant's initial buy-in.
            if (initialBuyin != 0) {
                ownerUsdToken.safeTransfer(applicant, initialBuyin);
            }
        }

        //</editor-fold desc="Reject and refund other applicants">

        //<editor-fold desc="Credit and share the accepted rider's initial buy-in">

        // The accepted rider's buy-in counts toward their hire-purchase total and is shared
        // with the investor pools and the owner immediately, like any other rider payment.
        // The funds were pulled into the contract by {actionRiderRegisterAsARider}.
        investment.riderPayinsHistory.riderAddress = _riderAddress;
        investment.riderPayinsHistory.totalAmountPaid += initialBuyin;
        stats.totalPayinsUsd += initialBuyin;

        HAsset storage asset = getAssetStorage(investment.assetId);
        HSharingBreakdown memory buyinBreakdown = calcSharingFormula(investment, asset, initialBuyin);
        recordDistribution(investment, _investmentId, buyinBreakdown, HPayoutType.RiderPaying);
        transferDistribution(investment, buyinBreakdown);

        //</editor-fold desc="Credit and share the accepted rider's initial buy-in">

        //<editor-fold desc="Mark the investment Hired">

        // Move the investment to Hired so the accepted rider can start paying.
        setInvestmentStatus(investment, HInvestmentStatus.Hired);

        //</editor-fold desc="Mark the investment Hired">
    }

    //</editor-fold desc="Action:Admin:Rider: Accept rider">

    //<editor-fold desc="Action:Admin:Rider: Extend rider paying">

    /// @notice Pushes the hired rider's next payment due date to a later time and optionally
    ///         slashes an amount from the rider's accumulated savings.
    /// @dev    Only an owner (admin: owner1 or owner2) may call this.
    ///         The opportunity must be {HInvestmentStatus.Hired}, i.e. a rider is
    ///         currently paying, and the new date must be later than the current
    ///         next-payment date. Extending the date gives the rider more time before
    ///         {actionRiderPayin} treats their next payment as late.
    ///         When `_slashAmount` is non-zero it must not exceed the rider's saved amount;
    ///         the savings are reduced by it and the amount is split to the owner and
    ///         investor pools exactly like a rider payment, recorded as
    ///         {HPayoutType.RiderSavingsSlash} payouts and tracked via {HRiderSavingsSlash}.
    ///         States updated: {HInvestment.riderNextPayinDate}, {HInvestment.riderSavings},
    ///         {riderSavingsSlashesList}, and the investment's slash and payout histories.
    /// @param _investmentId The id of the investment whose rider payment is extended.
    /// @param _newNextPayinDate The new timestamp at which the rider's next payment is due;
    ///        must be later than the investment's current next-payment date.
    /// @param _slashAmount Amount to slash from the rider's savings, in USDC base units
    ///        (6 decimals); 0 extends without slashing. Callers pass base units.
    function actionAdminExtendRiderPayingForInvestment(
        bytes32 _investmentId,
        uint256 _newNextPayinDate,
        uint256 _slashAmount
    ) external onlyOwners {
        // Get the modifiable investment (reverts if it is not registered).
        HInvestment storage investment = getInvestmentStorage(_investmentId);

        // The hire purchase must be running so there is a rider payment to extend.
        HInvestmentStatus[] memory allowedStatuses = new HInvestmentStatus[](1);
        allowedStatuses[0] = HInvestmentStatus.Hired;

        bool investmentNotHired = !isInvestmentStatus(_investmentId, allowedStatuses);
        if (investmentNotHired) revert HInvestmentNotHired(_investmentId);

        // The new date must push the deadline later, never earlier.
        bool newDateNotLater = _newNextPayinDate <= investment.riderNextPayinDate;
        if (newDateNotLater) {
            revert HInvestmentInvalidRiderNextPayinDate(_newNextPayinDate, investment.riderNextPayinDate);
        }

        // Apply the extended next-payment date.
        investment.riderNextPayinDate = _newNextPayinDate;

        // Optionally slash the rider's savings; zero means "extend only".
        bool slashRequested = _slashAmount != 0;
        if (slashRequested) {
            applyRiderSavingsSlash(investment, _investmentId, _slashAmount);
        }
    }

    //</editor-fold desc="Action:Admin:Rider: Extend rider paying">

    //<editor-fold desc="Action:Rider: Pay in">

    /// @notice Lets the hired rider make a periodic payment under a running hire purchase.
    /// @dev    The rider must be the one hired on an investment in {HInvestmentStatus.Hired},
    ///         must not have completed the target total, and must make a non-late payment of
    ///         at least {HInvestment.minimumRiderPeriodicPayingsUsd} plus the asset's
    ///         {HAsset.riderSlashableRepayableExtraCharge}. The extra charge is set aside as
    ///         the rider's savings, and the rest is split by {calcSharingFormula} and credited
    ///         to the owner and the senior/junior investor pools.
    ///         States updated: {riderPayinsList}, {riderPayins}, {HInvestment.riderPayinsHistory},
    ///         {HInvestment.riderNextPayinDate}, {ownerPayoutsList}, {investorPayoutList},
    ///         {HInvestment.riderSavings}, {HInvestment.investmentPayoutHistory} and the
    ///         per-investor payout histories.
    /// @param _investmentId The id of the investment being paid.
    /// @param _approvedUSD The USDC the rider is paying, in USDC base units (6 decimals);
    ///        must be at least the minimum plus the savings charge. Callers pass base units
    ///        (frontend: `parseUnits(x, 6)`).
    function actionRiderPayin(bytes32 _investmentId, uint256 _approvedUSD) external {
        //<editor-fold desc="Get the Investment">
        // Get the investment (reverts if it is not registered).
        HInvestment storage investment = getInvestmentStorage(_investmentId);
        //</editor-fold desc="Get the Investment">

        //<editor-fold desc="Ensure this status is Hired">

        // The hire purchase must be running.
        {
            HInvestmentStatus[] memory allowedStatuses = new HInvestmentStatus[](1);
            allowedStatuses[0] = HInvestmentStatus.Hired;

            bool investmentNotHired = !isInvestmentStatus(_investmentId, allowedStatuses);
            if (investmentNotHired) revert HInvestmentNotHired(_investmentId);
        }
        //</editor-fold desc="Ensure this status is Hired">

        //<editor-fold desc="Ensure this rider is hired for this investment">

        // Only the hired rider may pay.
        {
            bool notTheHiredRider = investment.riderWhoHiredIt != msg.sender;
            if (notTheHiredRider) revert HRiderNotHired(_investmentId, msg.sender);
        }
        //</editor-fold desc="Ensure this rider is hired for this investment">

        //<editor-fold desc="Get the asset & Payment History">

        // The asset defines the total the rider owes ({HAsset.sellPrice}) and the fixed
        // per-period extra charge, which is saved for them and refunded on ownership transfer.
        HAsset storage asset = getAssetStorage(investment.assetId);
        uint256 riderSavingsAmount = asset.riderSlashableRepayableExtraCharge;

        HPayingHistory storage payinsHistory = investment.riderPayinsHistory;
        //</editor-fold desc="Get the asset & Payment History">

        //<editor-fold desc="Ensure rider is not Done Paying all required">
        // The rider must not have finished paying.
        {
            bool paymentsCompleted = payinsHistory.totalAmountPaid >= asset.sellPrice;
            if (paymentsCompleted) revert HRiderPaymentsCompleted(_investmentId);
        }
        //</editor-fold desc="Ensure rider is not Done Paying all required">

        // The payment must meet the amount due for this period (the periodic minimum, capped
        // by the outstanding balance on the final instalment, plus the savings charge).
        {
            uint256 requiredThisPayment = calcRiderAmountToPayNow(investment, asset);

            bool belowMinimum = _approvedUSD < requiredThisPayment;
            if (belowMinimum) revert HRiderPayinBelowMinimum(_approvedUSD, requiredThisPayment);
        }

        // ...and must not be late.
        {
            bool paymentLate = block.timestamp > investment.riderNextPayinDate;
            if (paymentLate) revert HRiderPayinLate(_investmentId);
        }

        // Effects: record the payment and all accounting before any token movement.
        bytes32 riderId = bytes32(uint256(uint160(msg.sender)));
        riderPayinsList.push(
            HRiderPayin({
                riderId: riderId,
                investmentId: _investmentId,
                amountPaid: _approvedUSD,
                timePaid: block.timestamp,
                addressPaidInto: address(this)
            })
        );
        investment.riderPayinIndexes.push(riderPayinsList.length);

        // Gross rider payments feed the platform payins total.
        stats.totalPayinsUsd += _approvedUSD;

        // The rider's payment is the hire-purchase portion plus the refundable savings charge.
        uint256 hirePurchaseAmount = _approvedUSD - riderSavingsAmount;

        // Update the rider's payment history and push the next due date by one period.
        // Only the hire-purchase portion counts toward the total: the savings charge is set
        // aside for the rider and does not reduce what they still owe.
        payinsHistory.riderAddress = msg.sender;
        payinsHistory.totalAmountPaid += hirePurchaseAmount;
        payinsHistory.totalNumberOfTimesPaid += 1;
        investment.riderNextPayinDate += investment.periodicRiderPayingInMinutes * 60;

        // Split the hire-purchase portion and record the owner/investor shares.
        HSharingBreakdown memory breakdown = calcSharingFormula(investment, asset, hirePurchaseAmount);
        recordDistribution(investment, _investmentId, breakdown, HPayoutType.RiderPaying);

        // Set the rider's per-period savings aside (refunded on completion, slashable on default).
        recordRiderSavings(investment, riderSavingsAmount);

        // Record completion once the rider has paid the asset's total.
        bool riderCompleted = payinsHistory.totalAmountPaid >= asset.sellPrice;
        if (riderCompleted) {
            investment.timeRiderCompletedPayments = block.timestamp;
        }

        // Interactions: pull the payment in, pay everyone out, then hand over the title.
        ownerUsdToken.safeTransferFrom(msg.sender, address(this), _approvedUSD);
        transferDistribution(investment, breakdown);

        // Transfer ownership.
        if (riderCompleted) {
            actionTransferOwnershipToRider(msg.sender, _investmentId);
        }
    }

    //</editor-fold desc="Action:Rider: Pay in">

    //<editor-fold desc="Action:Rider: Complete payment">

    /// @notice Completes a hire purchase by transferring ownership of the asset to the rider.
    /// @dev    Only valid once the rider has finished paying. The rider's accumulated savings
    ///         are refunded to them and cleared, the investment is marked
    ///         {HInvestmentStatus.Complete}, the completion timestamps are recorded and the
    ///         investment is appended to the completed lists. It cannot run twice, so the
    ///         completion side effects happen exactly once.
    ///         States updated: {HInvestment.riderSavings}, {investmentsList},
    ///         {completedRiderInvestmentList} and {investmentsCompleted}.
    /// @param _rider The rider receiving ownership; must be the investment's hired rider.
    /// @param _investmentId The id of the investment being completed.
    function actionTransferOwnershipToRider(address _rider, bytes32 _investmentId) public {
        // Get the investment (reverts if it is not registered).
        HInvestment storage investment = getInvestmentStorage(_investmentId);

        // Only the hired rider may be handed ownership.
        {
            bool notTheHiredRider = _rider != investment.riderWhoHiredIt;
            if (notTheHiredRider) revert HRiderNotHired(_investmentId, _rider);
        }

        // The rider must have paid the asset's total before ownership changes hands.
        {
            HAsset storage asset = getAssetStorage(investment.assetId);
            HPayingHistory storage payinsHistory = investment.riderPayinsHistory;
            bool riderNotCompleted = payinsHistory.totalAmountPaid < asset.sellPrice;
            if (riderNotCompleted) revert HRiderPaymentsNotCompleted(_investmentId);
        }

        // The completion side effects must run exactly once.
        {
            HInvestmentStatus[] memory allowedStatuses = new HInvestmentStatus[](1);
            allowedStatuses[0] = HInvestmentStatus.Complete;

            bool investmentAlreadyComplete = isInvestmentStatus(_investmentId, allowedStatuses);
            if (investmentAlreadyComplete) revert HInvestmentAlreadyComplete(_investmentId);
        }

        // Refund the savings the rider accumulated and clear them so they cannot be refunded
        // twice. The savings were held in the contract, never transferred out.
        uint256 riderSavingsAmount = investment.riderSavings.totalAmountSaved;
        investment.riderSavings.totalAmountSaved = 0;
        stats.riderSavingsHeldUsd -= riderSavingsAmount;

        // Hand over ownership: mark complete and record the times.
        setInvestmentStatus(investment, HInvestmentStatus.Complete);
        investment.timeRiderCompletedPayments = block.timestamp;
        investment.timeNftTransferedToRider = block.timestamp;

        // Remember the completed investment. Positions are stored as `index + 1` (0 = not
        // registered), so the 1-based position is what gets appended.
        uint256 investmentIndexPlusOne = investments[_investmentId];
        completedRiderInvestmentList.push(investmentIndexPlusOne);
        investmentsCompleted.push(investmentIndexPlusOne);

        // Interactions: refund the savings and hand over the vehicle title last, after every
        // state write. The title was minted to this contract when the investment was funded.
        if (riderSavingsAmount != 0) {
            ownerUsdToken.safeTransfer(_rider, riderSavingsAmount);
        }

        // `transferFrom` rather than `safeTransferFrom` so a rider using a contract wallet
        // that does not implement the ERC721 receiver hook can still complete the purchase.
        vehicleNft.transferFrom(address(this), _rider, investment.nftTokenId);
    }

    //</editor-fold desc="Action:Rider: Complete payment">

    //</editor-fold desc="Actions">

    //<editor-fold desc="Getters">

    /// @notice Returns every aggregate statistic the frontend displays in one call.
    /// @dev    Counters are maintained in O(1) as the contract is used; the totals that
    ///         mirror list lengths are filled in here so there is a single source of truth.
    ///         Investor figures count filled slots, not distinct addresses.
    /// @return platformStats The platform-wide statistics.
    function getStats() external view returns (HStats memory) {
        HStats memory platformStats = stats;

        platformStats.totalAssets = assetsList.length;
        platformStats.totalInvestments = investmentsList.length;
        platformStats.totalInvestors = investorsList.length;
        platformStats.totalRiders = ridersList.length;
        platformStats.totalHireRequests = ridersHirePurchasesRequestsList.length;

        return platformStats;
    }

    //</editor-fold desc="Getters">
}
