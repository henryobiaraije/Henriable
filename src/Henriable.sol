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
HAssetNotActive,
HInvestment,
HInvestmentAlreadyExists,
HInvestmentHasInvestors,
HInvestmentInvalidAmount,
HInvestmentInvalidEndTime,
HInvestmentInvalidId,
HInvestmentInvalidMinimumRiderPeriodicPayings,
HInvestmentInvalidPeriodicRiderPayingInMinutes,
HInvestmentInvalidRiderInitialBuyin,
HInvestmentInvalidSettings,
HInvestmentInvalidStartTime,
HInvestmentNoOpenSlot,
HInvestmentNotAccepting,
HInvestmentNotActive,
HInvestmentNotPending,
HInvestmentStatus,
HInvestmentType,
HInvestor,
HInvestorAlreadyInvested,
HInvestorInvalidAge
} from "./types/common.sol";
import {HHelper} from "./helpers/HHelper.sol";
//</editor-fold desc="Imports">

/// @title The Henriable contract.
/// @author Obiaraije Henry
contract Henriable is HHelper {

    // Provides safeTransferFrom, which reverts on failure.
    using SafeERC20 for IERC20;

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

        // @todo: Add calc... to calculate that the pricing tally, e.g. that selling price would be nough to pay all investors and owner too.

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

    //<editor-fold desc="Action:Admin:Investment: Add investment">

    /// @notice Adds a new investment opportunity against an existing active asset.
    /// @dev    Only the contract owner (admin) may call this.
    ///         {HInvestment} contains mappings and therefore cannot be passed as a
    ///         calldata parameter, so the admin-supplied settings are taken as
    ///         individual arguments. Validates them, checks the level-1 settings
    ///         against the asset, forces the opportunity active and Pending, appends
    ///         it to {investmentsList}, records its position in the {investments}
    ///         index mapping and links it to its asset via {assetInvestments}.
    ///         States updated: {investmentsList}, {investments}, {assetInvestments}.
    /// @param _investmentId Unique, non-zero id of the new investment slot.
    /// @param _assetId Id of the asset to invest in; must exist and be active.
    /// @param _riderInitialBuyinUsd Initial rider buy-in, in USDC; must be non-zero.
    /// @param _periodicRiderPayingInMinutes Length of a rider period, in minutes; must be non-zero.
    /// @param _minimumRiderPeriodicPayingsUsd Minimum rider payment per period, in USDC; must be non-zero.
    function actionAdminAddInvestment(
        bytes32 _investmentId,
        bytes32 _assetId,
        uint256 _riderInitialBuyinUsd,
        uint256 _periodicRiderPayingInMinutes,
        uint256 _minimumRiderPeriodicPayingsUsd
    ) external onlyOwner {

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

        // A newly added opportunity always starts active and Pending.
        newInvestment.active = true;
        newInvestment.status = HInvestmentStatus.Pending;

        // ...record its position as `index + 1` (length after push), which gives
        // O(1) lookups and lets 0 mean "not registered"...
        investments[_investmentId] = investmentsList.length;

        // ...and link it to its asset so the asset can enumerate its investments.
        assetInvestments[_assetId].push(investmentsList.length - 1);
    }

    //</editor-fold desc="Action:Admin:Investment: Add investment">

    //<editor-fold desc="Action:Admin:Investment: Change investment status">

    /// @notice Enables or disables an investment opportunity.
    /// @dev    Only the contract owner (admin) may call this.
    ///         The investment's active flag may only change while no investor has
    ///         joined it; once the senior or junior pool has any investor, the
    ///         opportunity is locked.
    ///         States updated: {investmentsList}.
    /// @param _investmentId The id of the investment to update.
    /// @param _status The new active status.
    function actionAdminChangeInvestmentStatus(bytes32 _investmentId, bool _status) external onlyOwner {
        // Get the modifiable investment (reverts if it is not registered).
        HInvestment storage investment = getInvestmentStorage(_investmentId);

        // The active flag may only change while nobody has invested yet.
        bool investmentHasInvestors =
            investment.seniorInvestorsList.length != 0 || investment.juniorInvestorsList.length != 0;
        if (investmentHasInvestors) revert HInvestmentHasInvestors(_investmentId);

        // Apply the requested status to the investment.
        investment.active = _status;
    }

    //</editor-fold desc="Action:Admin:Investment: Change investment status">

    //<editor-fold desc="Action:Admin:Investment: Set next investment times">

    /// @notice Sets the start and end of the next investment round for an investment.
    /// @dev    Only the contract owner (admin) may call this.
    ///         The opportunity must still be Pending and its asset active, and the
    ///         round must be in the future with `_endTime` after `_startTime`.
    ///         States updated: {investmentsList}.
    /// @param _investmentId The id of the investment to schedule.
    /// @param _startTime Timestamp at which the next investment round starts; must be in the future.
    /// @param _endTime Timestamp at which the next investment round ends; must be after _startTime.
    function actionAdminSetNextInvestmentTimes(bytes32 _investmentId, uint256 _startTime, uint256 _endTime)
    external
    onlyOwner
    {
        // Get the modifiable investment (reverts if it is not registered).
        HInvestment storage investment = getInvestmentStorage(_investmentId);

        // Times may only be set while the opportunity is still Pending.
        HInvestmentStatus[] memory allowedStatuses = new HInvestmentStatus[](1);
        allowedStatuses[0] = HInvestmentStatus.Pending;

        bool investmentNotPending = !isInvestmentStatus(_investmentId, allowedStatuses);
        if (investmentNotPending) revert HInvestmentNotPending(_investmentId);

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
    /// @dev    Only the contract owner (admin) may call this.
    ///         The opportunity must still be Pending; both times are reset to 0.
    ///         States updated: {investmentsList}.
    /// @param _investmentId The id of the investment whose round is cleared.
    function actionAdminClearNextInvestmentsTimes(bytes32 _investmentId) external onlyOwner {
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
    ///         States updated: {investorsList}, {investors}, and the chosen tier's
    ///         list and mapping inside {investmentsList}.
    /// @param _investor The investor profile (name, country, age) to create or update.
    /// @param _investmentType The tier to invest in (Senior or Junior).
    /// @param _investmentId The id of the investment to invest in.
    /// @param _approvedUSDAmount The USDC amount approved for this slot; must equal the slot amount.
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
        mapping(address => uint256) storage theInvestors = _investmentType == HInvestmentType.Senior
            ? investment.seniorInvestors
            : investment.juniorInvestors;

        address[] storage theInvestorsList = _investmentType == HInvestmentType.Senior
            ? investment.seniorInvestorsList
            : investment.juniorInvestorsList;

        uint256 theInvestorBuyingPrice = _investmentType == HInvestmentType.Senior
            ? asset.oneSeniorInvestorBuyingPrice
            : asset.oneJuniorInvestorBuyingPrice;

        uint256 theInvestorSlotsNeeded = _investmentType == HInvestmentType.Senior
            ? asset.totalNumberOfSeniorInvestorsNeeded
            : asset.totalNumberOfJuniorInvestorsNeeded;

        // An address may take at most one slot per tier.
        {
            bool investorAlreadyInvested = theInvestors[msg.sender] != 0;
            if (investorAlreadyInvested) revert HInvestorAlreadyInvested(_investmentId, msg.sender);
        }

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

        // Let the status helper react (e.g. mark the opportunity done once full).
        maybeUpdateInvestmentStatus(_investmentId);

        // Pull the USDC from the investor into the contract (reverts on failure).
        ownerUsdToken.safeTransferFrom(msg.sender, address(this), requiredAmount);
    }

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

    //</editor-fold desc="Action:Investor: Invest">

    //</editor-fold desc="Actions">
}