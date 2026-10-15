// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {HenriableVehicleNFT} from "../../src/HenriableVehicleNFT.sol";

/// @title Tests for {HenriableVehicleNFT.tokenURI}.
/// @notice Metadata is a base64 data URI: JSON wrapping an inline base64 SVG, carrying the
///         token id and the live owner, so titles are viewable with no off-chain hosting.
contract HenriableVehicleNFTTokenUriTest is Test {
    address internal constant MINTER = address(0x1111);
    address internal constant RECIPIENT = address(0xB0B);
    address internal constant NEW_OWNER = address(0xCAFE);

    bytes internal constant JSON_PREFIX = bytes("data:application/json;base64,");

    HenriableVehicleNFT internal nft;

    function setUp() public {
        nft = new HenriableVehicleNFT(address(this));
        nft.setMinter(MINTER);
    }

    function test_TokenUri_Reverts_WhenTokenDoesNotExist() public {
        vm.expectRevert();
        nft.tokenURI(1);
    }

    function test_TokenUri_EncodesNameImageAndOwner() public {
        vm.prank(MINTER);
        nft.mint(RECIPIENT);

        string memory uri = nft.tokenURI(1);
        assertTrue(_startsWith(bytes(uri), JSON_PREFIX));

        string memory json = _decode(uri);
        assertTrue(_contains(json, '"name":"Henriable Vehicle Title #1"'));
        assertTrue(_contains(json, '"image":"data:image/svg+xml;base64,'));
        assertTrue(_contains(json, Strings.toHexString(RECIPIENT)));
    }

    function test_TokenUri_ReflectsCurrentOwner() public {
        vm.prank(MINTER);
        nft.mint(RECIPIENT);

        vm.prank(RECIPIENT);
        nft.transferFrom(RECIPIENT, NEW_OWNER, 1);

        string memory json = _decode(nft.tokenURI(1));
        assertTrue(_contains(json, Strings.toHexString(NEW_OWNER)));
        assertFalse(_contains(json, Strings.toHexString(RECIPIENT)));
    }

    function test_TokenUri_IncludesAssetAndRiderFromPlatform() public {
        MockTitleSource source = new MockTitleSource();
        nft.setMinter(address(source));
        source.mint(nft, RECIPIENT);

        string memory json = _decode(nft.tokenURI(1));
        assertTrue(_contains(json, '"trait_type":"Asset","value":"Keke-0001-2026"'));
        assertTrue(_contains(json, Strings.toHexString(address(0xBEEF))));
    }

    // Strips the data-URI prefix and base64-decodes the JSON payload.
    function _decode(string memory uri) internal pure returns (string memory) {
        bytes memory raw = bytes(uri);
        bytes memory payload = new bytes(raw.length - JSON_PREFIX.length);
        for (uint256 i = 0; i < payload.length; i++) {
            payload[i] = raw[i + JSON_PREFIX.length];
        }
        return string(Base64.decode(string(payload)));
    }

    function _startsWith(bytes memory haystack, bytes memory prefix) internal pure returns (bool) {
        if (prefix.length > haystack.length) return false;
        for (uint256 i = 0; i < prefix.length; i++) {
            if (haystack[i] != prefix[i]) return false;
        }
        return true;
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0 || n.length > h.length) return false;
        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool matched = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) return true;
        }
        return false;
    }
}

/// @notice Minimal platform stand-in that answers {HenriableVehicleNFT}'s metadata read.
contract MockTitleSource {
    function getTitleInfo(uint256) external pure returns (bytes32, address) {
        return (bytes32("Keke-0001-2026"), address(0xBEEF));
    }

    function mint(HenriableVehicleNFT nft, address to) external returns (uint256) {
        return nft.mint(to);
    }
}
