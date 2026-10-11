// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Henriable} from "../src/Henriable.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

/// @title Deploy script for the Henriable platform.
/// @author Obiaraije Henry
/// @notice Deploys {Henriable}, owned by the deployer. It points Henriable at the USDC
///         token at `USDC_ADDRESS` when that is set, otherwise it deploys a local
///         {MockUSDC} first so Anvil deployments are self-contained.
/// @dev    The deployer key is read from `DEPLOYER_PRIVATE_KEY`; the wrapper shell
///         scripts (script/deploy.sh for Anvil, script/deploy-sepolia.sh for Sepolia)
///         set the environment variables and the RPC/verify flags.
contract DeployScript is Script {
    /// @notice Deploys Henriable, and a mock USDC when no token is configured.
    /// @return usdc The USDC token Henriable points at.
    /// @return henriable The deployed {Henriable} contract.
    function run() external returns (IERC20 usdc, Henriable henriable) {
        // Reads the deployer key exposed by the wrapper shell script.
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // The deployer becomes the initial owner of the platform.
        address initialOwner = vm.addr(deployerPrivateKey);

        // A configured USDC address (e.g. real USDC on Sepolia) is used as-is; when it
        // is unset a local mock token is deployed instead.
        address usdcAddress = vm.envOr("USDC_ADDRESS", address(0));

        // Everything inside startBroadcast is sent to the network as a transaction.
        vm.startBroadcast(deployerPrivateKey);

        bool usdcNotConfigured = usdcAddress == address(0);
        if (usdcNotConfigured) {
            usdcAddress = address(new MockUSDC());
            console.log("MockUSDC deployed at:", usdcAddress);
        } else {
            console.log("Using existing USDC at:", usdcAddress);
        }

        usdc = IERC20(usdcAddress);
        henriable = new Henriable(initialOwner, usdc);

        vm.stopBroadcast();

        console.log("Henriable deployed at:", address(henriable));
        console.log("Initial owner:", initialOwner);
    }
}
