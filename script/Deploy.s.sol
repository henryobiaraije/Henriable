// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Henriable} from "../src/Henriable.sol";
import {HenriableVehicleNFT} from "../src/HenriableVehicleNFT.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

/// @title Deploy script for the Henriable platform.
/// @author Obiaraije Henry
/// @notice Deploys the whole platform in one run: the vehicle-title NFT collection, the
///         {Henriable} contract, and (only when no USDC is configured) a local {MockUSDC}.
///         It points Henriable at the USDC token at `USDC_ADDRESS` when that is set,
///         otherwise it deploys a local {MockUSDC} first so deployments are self-contained.
/// @dev    The deployer key is read from `DEPLOYER_PRIVATE_KEY`; the wrapper shell script
///         (script/deploy-sepolia.sh) sets the environment variables and the RPC/verify
///         flags. Every deployed address is written to `deployments/<chainId>.json` so the
///         frontend can read them without typing anything by hand. The deployer owns the
///         NFT collection and sets the deployed {Henriable} as its minter.
contract DeployScript is Script {
    //<editor-fold desc="Constants">

    /// @notice Mock USDC minted to the deployer on local deployments (1 billion USDC).
    /// @dev    6-decimal token, so the base amount is multiplied by 10 ** 6.
    uint256 private constant HMOCK_USDC_INITIAL_SUPPLY = 1_000_000_000 * 10 ** 6;

    //</editor-fold desc="Constants">

    /// @notice Deploys the vehicle-title NFT, Henriable, and a mock USDC when none is set.
    /// @return usdc The USDC token Henriable points at.
    /// @return vehicleNft The deployed vehicle-title NFT collection.
    /// @return henriable The deployed {Henriable} contract.
    function run() external returns (IERC20 usdc, HenriableVehicleNFT vehicleNft, Henriable henriable) {
        // Reads the deployer key exposed by the wrapper shell script.
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // The deployer becomes the initial owner of the platform and of the NFT collection.
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

            // Fund the deployer so local runs have plenty of USDC to test with.
            MockUSDC(usdcAddress).mint(initialOwner, HMOCK_USDC_INITIAL_SUPPLY);
            console.log("MockUSDC minted to owner:", HMOCK_USDC_INITIAL_SUPPLY);
        } else {
            console.log("Using existing USDC at:", usdcAddress);
        }

        usdc = IERC20(usdcAddress);

        // Deploy the title collection first, then the platform that mints into it, then
        // authorize the platform as its only minter.
        vehicleNft = new HenriableVehicleNFT(initialOwner);
        henriable = new Henriable(initialOwner, usdc, vehicleNft);
        vehicleNft.setMinter(address(henriable));

        vm.stopBroadcast();

        console.log("HenriableVehicleNFT deployed at:", address(vehicleNft));
        console.log("Henriable deployed at:", address(henriable));
        console.log("Initial owner:", initialOwner);

        _writeDeploymentManifest(usdc, vehicleNft, henriable, initialOwner);
    }

    /// @notice Writes every deployed address to `deployments/<chainId>.json`.
    /// @dev    The frontend reads this file so no address is copied by hand. It is written on
    ///         both broadcast and simulation runs; on simulation the CREATE addresses match
    ///         because they are nonce-derived.
    /// @param usdc The USDC token address.
    /// @param vehicleNft The vehicle-title NFT address.
    /// @param henriable The platform address.
    /// @param initialOwner The owner the platform and collection were deployed with.
    function _writeDeploymentManifest(
        IERC20 usdc,
        HenriableVehicleNFT vehicleNft,
        Henriable henriable,
        address initialOwner
    ) internal {
        string memory obj = "deployment";
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeAddress(obj, "usdc", address(usdc));
        vm.serializeAddress(obj, "vehicleNft", address(vehicleNft));
        vm.serializeAddress(obj, "henriable", address(henriable));
        vm.serializeAddress(obj, "owner", initialOwner);
        string memory json = vm.serializeUint(obj, "timestamp", block.timestamp);

        vm.createDir("deployments", true);
        string memory path = string.concat("deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);
        console.log("Deployment manifest written to:", path);
    }
}
