// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC
/// @author Obiaraije Henry
/// @notice Minimal 6-decimal ERC20 token standing in for USDC on a local network.
/// @dev    Used by the deploy script; the platform only touches it through {IERC20}.
contract MockUSDC is ERC20 {
    //<editor-fold desc="Constructor">

    /// @notice Deploys the mock token with the USDC name and symbol.
    constructor() ERC20("USD Coin", "USDC") {}

    //</editor-fold desc="Constructor">

    //<editor-fold desc="Overrides">

    /// @notice USDC uses 6 decimals rather than the ERC20 default of 18.
    /// @return The number of decimals, 6.
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    //</editor-fold desc="Overrides">
}
