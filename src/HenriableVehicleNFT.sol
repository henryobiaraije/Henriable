// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

//<editor-fold desc="Imports">

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {HVehicleNftUnauthorizedMinter} from "./types/common.sol";

//</editor-fold desc="Imports">

/// @notice The slice of the platform the title NFT reads for its metadata.
interface IVehicleTitleInfo {
    /// @param tokenId The title's token id.
    /// @return assetName The bytes32 asset name.
    /// @return rider The rider who hired the asset, or address(0).
    function getTitleInfo(uint256 tokenId) external view returns (bytes32 assetName, address rider);
}

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

    //<editor-fold desc="Metadata">

    /// @notice Returns the token's metadata as an on-chain base64 data URI.
    /// @dev    ERC721 metadata JSON with an inline base64 SVG image, so titles render in
    ///         Etherscan, wallets and marketplaces with no off-chain hosting. The owner on the
    ///         card is read live, so it updates when the platform transfers the deed. Reverts
    ///         for a non-existent token (via {_requireOwned}).
    /// @param tokenId The title's token id.
    /// @return A `data:application/json;base64,...` URI.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        address owner = _ownerOf(tokenId);
        (bytes32 assetName, address rider) = _titleInfo(tokenId);
        string memory asset = _bytes32ToString(assetName);

        string memory svg = _renderSvg(tokenId, owner, asset, rider);
        string memory json =
            string.concat(
                '{"name":"Henriable Vehicle Title #',
                Strings.toString(tokenId),
                '","description":"A Henriable vehicle title deed. Minted by the Henriable platform and transferable to the rider once the hire purchase completes.",',
                '"image":"data:image/svg+xml;base64,',
                Base64.encode(bytes(svg)),
                '","attributes":[{"trait_type":"Instrument","value":"Vehicle Title"}',
                bytes(asset).length > 0
                    ? string.concat(',{"trait_type":"Asset","value":"', asset, '"}')
                    : "",
                rider == address(0)
                    ? ""
                    : string.concat(
                        ',{"trait_type":"Rider","value":"',
                        Strings.toHexString(rider),
                        '"}'
                    ),
                ',{"trait_type":"Owner","value":"',
                Strings.toHexString(owner),
                '"}]}'
            );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    /// @notice Renders the title card as an SVG.
    /// @param tokenId The title's token id.
    /// @param owner The current owner, shown on the card.
    /// @param asset The asset name (empty when unknown).
    /// @param rider The hired rider (address(0) when unknown), shown on the card.
    /// @return The SVG markup.
    function _renderSvg(
        uint256 tokenId,
        address owner,
        string memory asset,
        address rider
    ) internal pure returns (string memory) {
        return
            string.concat(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 600" width="600" height="600">',
                '<rect width="600" height="600" fill="#162022"/>',
                '<rect x="32" y="32" width="536" height="536" rx="28" fill="#202b2d" stroke="#ffe629" stroke-width="4"/>',
                '<text x="64" y="124" fill="#ffe629" font-family="monospace" font-size="30" font-weight="700">HENRIABLE</text>',
                '<text x="64" y="162" fill="#b7c2bf" font-family="monospace" font-size="16">VEHICLE TITLE #',
                Strings.toString(tokenId),
                "</text>",
                '<text x="64" y="260" fill="#ffffff" font-family="monospace" font-size="40" font-weight="700">',
                bytes(asset).length > 0 ? asset : "Vehicle Title",
                "</text>",
                '<text x="64" y="500" fill="#b7c2bf" font-family="monospace" font-size="15">owner ',
                Strings.toHexString(owner),
                "</text>",
                rider == address(0)
                    ? ""
                    : string.concat(
                        '<text x="64" y="528" fill="#b7c2bf" font-family="monospace" font-size="15">rider ',
                        Strings.toHexString(rider),
                        "</text>"
                    ),
                '<text x="64" y="556" fill="#6f7c78" font-family="monospace" font-size="13">on-chain title deed</text>',
                "</svg>"
            );
    }

    /// @notice Reads the asset name and rider from the platform (the minter).
    /// @dev    Returns zero values when the minter is unset or is not a contract that answers,
    ///         so metadata degrades gracefully instead of reverting.
    /// @param tokenId The title's token id.
    /// @return assetName The bytes32 asset name, or bytes32(0).
    /// @return rider The rider, or address(0).
    function _titleInfo(uint256 tokenId) internal view returns (bytes32 assetName, address rider) {
        address source = minter;
        if (source == address(0) || source.code.length == 0) return (bytes32(0), address(0));
        try IVehicleTitleInfo(source).getTitleInfo(tokenId) returns (bytes32 name_, address rider_) {
            return (name_, rider_);
        } catch {
            return (bytes32(0), address(0));
        }
    }

    /// @notice Decodes a bytes32 asset name into a trimmed ASCII string.
    /// @param value The bytes32 to decode.
    /// @return The decoded string (up to the first zero byte).
    function _bytes32ToString(bytes32 value) internal pure returns (string memory) {
        uint256 length = 0;
        while (length < 32 && value[length] != bytes1(0)) {
            length++;
        }
        bytes memory out = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            out[i] = value[i];
        }
        return string(out);
    }

    //</editor-fold desc="Metadata">

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
