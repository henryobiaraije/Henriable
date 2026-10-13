// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title HMath
/// @author Obiaraije Henry
/// @notice Stateless numeric helpers shared across the Henriable contracts.
library HMath {
    //<editor-fold desc="Min/Max">

    /// @notice Returns the smaller of two values.
    /// @param a First value to compare.
    /// @param b Second value to compare.
    /// @return The smaller of `a` and `b`.
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        bool aIsSmaller = a < b;
        if (aIsSmaller) {
            return a;
        }
        return b;
    }

    /// @notice Returns the larger of two values.
    /// @param a First value to compare.
    /// @param b Second value to compare.
    /// @return The larger of `a` and `b`.
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        bool aIsLarger = a > b;
        if (aIsLarger) {
            return a;
        }
        return b;
    }

    //</editor-fold desc="Min/Max">
}
