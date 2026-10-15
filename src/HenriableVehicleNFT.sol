// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

//<editor-fold desc="Imports">

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {HVehicleNftUnauthorizedMinter} from "./types/common.sol";

//</editor-fold desc="Imports">

/// @title Henriable vehicle-title NFT.
/// @author Obiaraije Henry
/// @notice An ERC721 that represents the title deed of one physical asset. The platform
///         mints it to itself once an investment is fully funded and transfers it to the
///         rider when the hire purchase is paid in full. The token is a standard,
///         transferable ERC721 after the rider receives it.
/// @dev    Kept as its own contract (not inherited by {Henriable}) so the platform's
///         business logic stays under the EIP-170 code-size limit. Minting is gated by a
///         single {minter} address, which the owning deployer sets to the {Henriable}
///         address during deployment; the deployer keeps admin control of the collection.
contract HenriableVehicleNFT is ERC721, Ownable {
    //<editor-fold desc="States">

    //<editor-fold desc="State: Minter">

    /// @notice The only address allowed to mint titles (the {Henriable} platform).
    /// @dev    address(0) means no address can mint until the owner sets it.
    address internal minter;

    //</editor-fold desc="State: Minter">

    //<editor-fold desc="State: Tokens">

    /// @notice Id that will be assigned to the next minted title.
    /// @dev    Ids start at 1 so 0 keeps meaning "no title", matching the platform.
    uint256 internal nextTokenId;

    //</editor-fold desc="State: Tokens">

    //</editor-fold desc="States">

    //<editor-fold desc="Constructor">

    /// @notice Deploys the collection with its name and symbol.
    /// @param initialOwner The address that owns the collection and may set the minter.
    constructor(address initialOwner) ERC721("Henriable Vehicle Title", "HVT") Ownable(initialOwner) {}

    //</editor-fold desc="Constructor">

    //<editor-fold desc="Modifiers">

    /// @notice Restricts a function to the configured {minter}.
    /// @dev    Reverts with {HVehicleNftUnauthorizedMinter} when the caller is not the minter.
    modifier onlyMinter() {
        bool notTheMinter = msg.sender != minter;
        if (notTheMinter) revert HVehicleNftUnauthorizedMinter(msg.sender);
        _;
    }

    //</editor-fold desc="Modifiers">

    //<editor-fold desc="Actions">

    /// @notice Sets the address allowed to mint titles, typically the platform.
    /// @dev    Only the collection owner may call this. Pass address(0) to disable minting.
    ///         States updated: {minter}.
    /// @param newMinter The address allowed to mint, or address(0) to disable minting.
    function setMinter(address newMinter) external onlyOwner {
        minter = newMinter;
    }

    /// @notice Mints the next title to an address.
    /// @dev    Only the {minter} may call this. Ids are assigned sequentially from 1.
    ///         States updated: {nextTokenId}.
    /// @param to The address that will own the newly minted title.
    /// @return tokenId The id of the newly minted title.
    function mint(address to) external onlyMinter returns (uint256 tokenId) {
        nextTokenId += 1;
        tokenId = nextTokenId;

        // Mint without the receiver check: the minter always mints to the platform, which
        // holds the title until the rider finishes paying.
        _mint(to, tokenId);
    }

    //</editor-fold desc="Actions">

    //<editor-fold desc="Getters">

    /// @notice Returns the address allowed to mint titles.
    /// @return The configured minter, or address(0) when unset.
    function getMinter() external view returns (address) {
        return minter;
    }

    /// @notice Returns the id that will be assigned to the next minted title.
    /// @return The next token id.
    function getNextTokenId() external view returns (uint256) {
        return nextTokenId;
    }

    //</editor-fold desc="Getters">
}
