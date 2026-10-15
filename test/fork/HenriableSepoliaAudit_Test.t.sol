// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {
    HAsset,
    HInvestorPayout,
    HInvestorPayoutsHistory,
    HInvestmentPayoutsHistory,
    HInvestmentStatus,
    HOwnerPayout,
    HOwnerPayoutsHistory,
    HStats
} from "../../src/types/common.sol";
import {Henriable} from "../../src/Henriable.sol";

/// @title Fork audit of the live Sepolia Henriable deployment.
/// @notice Reads the deployed contract at its current block and reconciles every number the
///         platform records: the per-investor and owner payout histories, the aggregate
///         investment payout history, and the platform stats. It then compares what each
///         investor and the owner were promised (buying price + profit, and ownerProfit)
///         against what they were actually paid, and fails when a party was underpaid.
/// @dev    Opt-in: it runs only when `RUN_SEPOLIA_AUDIT=1` and `SEPOLIA_RPC_URL` are set, so a
///         normal `forge test` skips it. Override the target with `HENRIABLE_ADDRESS`.
///         Run it with:
///           RUN_SEPOLIA_AUDIT=1 forge test --match-path test/fork/HenriableSepoliaAudit_Test.t.sol -vv
contract HenriableSepoliaAuditTest is Test {
    /// @notice Henriable deployment audited by default (Sepolia).
    address internal constant DEFAULT_HENRIABLE = 0x710f7739060300a6AB821f1B4A4c1428fF86BfB0;

    /// @dev Bundles one investment's economics and recorded payouts to keep the audit off the
    ///      stack limit.
    struct InvestmentAudit {
        bytes32 investmentId;
        bytes32 assetId;
        HInvestmentStatus status;
        uint256 sellPrice;
        uint256 seniorPerSeat;
        uint256 juniorPerSeat;
        uint256 seniorTarget;
        uint256 juniorTarget;
        uint256 totalPayout;
        uint256 ownerProfit;
        uint256 investmentHistoryTotal;
        uint256 ownerPaid;
        uint256 seniorPaid;
        uint256 juniorPaid;
    }

    function test_SepoliaAudit_ReconcilesPayoutsAndStats() public {
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string(""));
        bool enabled = vm.envOr("RUN_SEPOLIA_AUDIT", false);

        bool cannotRun = !enabled || bytes(rpc).length == 0;
        if (cannotRun) {
            vm.skip(true);
            return;
        }

        vm.createSelectFork(rpc);
        Henriable h = Henriable(vm.envOr("HENRIABLE_ADDRESS", DEFAULT_HENRIABLE));

        HStats memory s = h.getStats();
        uint256 investmentCount = h.getInvestmentsCount();

        console.log("=== Sepolia Henriable audit ===");
        console.log("contract", address(h));
        console.log("block", block.number);

        _reconcileGlobalPayouts(h, s);

        for (uint256 index = 0; index < investmentCount; index++) {
            _auditInvestment(h, s, index);
        }
    }

    /// @notice Checks the platform stats equal the sums of the underlying payout entries.
    function _reconcileGlobalPayouts(Henriable h, HStats memory s) internal view {
        uint256 ownerEntriesTotal = _sumOwnerEntries(h);
        uint256 investorEntriesTotal = _sumInvestorEntries(h);

        console.log("");
        console.log("--- stats vs raw payout entries ---");
        console.log("owner payouts (stats / entries)", s.totalOwnerPayoutsUsd, ownerEntriesTotal);
        console.log(
            "investor payouts (stats / entries)",
            s.totalSeniorPayoutsUsd + s.totalJuniorPayoutsUsd,
            investorEntriesTotal
        );

        assertEq(ownerEntriesTotal, s.totalOwnerPayoutsUsd, "owner stats != sum of owner payout entries");
        assertEq(
            investorEntriesTotal,
            s.totalSeniorPayoutsUsd + s.totalJuniorPayoutsUsd,
            "investor stats != sum of investor payout entries"
        );
    }

    function _sumOwnerEntries(Henriable h) internal view returns (uint256 total) {
        uint256 count = h.getOwnerPayoutsCount();
        for (uint256 i = 0; i < count; i++) {
            total += h.getOwnerPayoutAt(i).amountPaid;
        }
    }

    function _sumInvestorEntries(Henriable h) internal view returns (uint256 total) {
        uint256 count = h.getInvestorPayoutsCount();
        for (uint256 i = 0; i < count; i++) {
            total += h.getInvestorPayoutAt(i).amountPaid;
        }
    }

    /// @notice Builds the audit record for one investment, logs it and asserts its economics.
    function _auditInvestment(Henriable h, HStats memory s, uint256 index) internal view {
        InvestmentAudit memory a;

        (a.investmentId, , a.assetId, , , , , a.status) = h.getInvestmentCore(index);

        HAsset memory asset = h.getAsset(a.assetId);
        a.sellPrice = asset.sellPrice;
        a.ownerProfit = asset.ownerProfit;
        a.seniorPerSeat = asset.oneSeniorInvestorBuyingPrice + asset.oneSeniorInvestorProfit;
        a.juniorPerSeat = asset.oneJuniorInvestorBuyingPrice + asset.oneJuniorInvestorProfit;
        a.seniorTarget = asset.totalNumberOfSeniorInvestorsNeeded * a.seniorPerSeat;
        a.juniorTarget = asset.totalNumberOfJuniorInvestorsNeeded * a.juniorPerSeat;
        a.totalPayout = a.seniorTarget + a.juniorTarget + a.ownerProfit;

        HInvestmentPayoutsHistory memory iph = h.getInvestmentPayoutHistory(index);
        a.investmentHistoryTotal = iph.totalAmountPaid;

        HOwnerPayoutsHistory memory oph = h.getOwnerPayoutHistory(a.investmentId);
        a.ownerPaid = oph.totalAmountPaid;

        a.seniorPaid = _auditTier(h, a.investmentId, h.getSeniorInvestorsList(index), a.seniorPerSeat, "senior");
        a.juniorPaid = _auditTier(h, a.investmentId, h.getJuniorInvestorsList(index), a.juniorPerSeat, "junior");

        _logInvestment(a);

        // The aggregate investment history equals the owner + senior + junior parts.
        assertEq(
            a.ownerPaid + s.totalSeniorPayoutsUsd + s.totalJuniorPayoutsUsd,
            a.investmentHistoryTotal,
            "investment payout history != owner + senior + junior"
        );
        assertEq(a.seniorPaid, s.totalSeniorPayoutsUsd, "senior pool paid != sum of senior investor histories");
        assertEq(a.juniorPaid, s.totalJuniorPayoutsUsd, "junior pool paid != sum of junior investor histories");

        // Every investor pool and the owner must be paid in full.
        assertGe(a.seniorPaid, a.seniorTarget, "senior investors underpaid vs buying+profit");
        assertGe(a.juniorPaid, a.juniorTarget, "junior investors underpaid vs buying+profit");
        assertGe(a.ownerPaid, a.ownerProfit, "owner underpaid vs ownerProfit");
    }

    function _logInvestment(InvestmentAudit memory a) internal pure {
        console.log("");
        console.log("=== investment ===");
        console.logBytes32(a.investmentId);
        console.log("status (enum)", uint256(a.status));
        console.log("sellPrice", a.sellPrice);
        console.log("sellPrice covers total payout", a.sellPrice >= a.totalPayout);
        console.log("senior paid / target", a.seniorPaid, a.seniorTarget);
        console.log("junior paid / target", a.juniorPaid, a.juniorTarget);
        console.log("owner paid / target", a.ownerPaid, a.ownerProfit);
        console.log("investment payout history total", a.investmentHistoryTotal);
    }

    /// @dev Sums each distinct investor's payout history once (an address may hold several
    ///      seats) and logs the actual vs the expected buying-price-plus-profit total.
    function _auditTier(
        Henriable h,
        bytes32 investmentId,
        address[] memory investors,
        uint256 perSeatTarget,
        string memory tierName
    ) internal view returns (uint256 poolPaid) {
        uint256 n = investors.length;
        for (uint256 i = 0; i < n; i++) {
            address who = investors[i];

            bool seen = false;
            for (uint256 j = 0; j < i; j++) {
                if (investors[j] == who) {
                    seen = true;
                    break;
                }
            }
            if (seen) continue;

            uint256 seats = 0;
            for (uint256 j = 0; j < n; j++) {
                if (investors[j] == who) {
                    seats += 1;
                }
            }

            HInvestorPayoutsHistory memory history = h.getInvestorPayoutHistory(investmentId, who);
            poolPaid += history.totalAmountPaid;

            uint256 expected = seats * perSeatTarget;
            console.log("");
            console.log(string.concat(tierName, " investor"), who);
            console.log("  seats", seats);
            console.log("  paid (base units)", history.totalAmountPaid);
            console.log("  expected buying+profit (base units)", expected);
        }
    }
}
