// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {HMath} from "../../../src/helpers/HMath.sol";

/// @title Tests for {HMath.min}.
/// @notice The helper returns the smaller of two unsigned integers.
contract HMathMinTest is Test {
    function test_Min_ReturnsFirst_WhenFirstIsSmaller() public pure {
        uint256 smaller = HMath.min(3, 7);

        assertEq(smaller, 3);
    }

    function test_Min_ReturnsSecond_WhenSecondIsSmaller() public pure {
        uint256 smaller = HMath.min(9, 4);

        assertEq(smaller, 4);
    }

    function test_Min_ReturnsEither_WhenValuesAreEqual() public pure {
        uint256 smaller = HMath.min(5, 5);

        assertEq(smaller, 5);
    }

    function test_Min_ReturnsZero_WhenOneValueIsZero() public pure {
        assertEq(HMath.min(0, 6), 0);
        assertEq(HMath.min(6, 0), 0);
    }

    function test_Min_ReturnsZero_WhenBothValuesAreZero() public pure {
        uint256 smaller = HMath.min(0, 0);

        assertEq(smaller, 0);
    }

    function test_Min_ReturnsSecond_WhenFirstIsMaxUint256() public pure {
        uint256 smaller = HMath.min(type(uint256).max, 1);

        assertEq(smaller, 1);
    }
}
