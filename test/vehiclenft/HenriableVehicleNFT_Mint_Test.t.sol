// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {HVehicleNftUnauthorizedMinter} from "../../src/types/common.sol";
import {HenriableVehicleNFT} from "../../src/HenriableVehicleNFT.sol";

/// @title Tests for {HenriableVehicleNFT.mint}.
/// @notice Only the configured minter may mint, ids are assigned sequentially from 1, and the
///         token is owned by the requested address.
contract HenriableVehicleNFTMintTest is Test {
    address internal constant MINTER = address(0x1111);
    address internal constant RECIPIENT = address(0xB0B);
    address internal constant NON_MINTER = address(0xDEAD);

    HenriableVehicleNFT internal nft;

    function setUp() public {
        nft = new HenriableVehicleNFT(address(this));
        nft.setMinter(MINTER);
    }

    function test_Mint_MintsTitleToRecipient() public {
        vm.prank(MINTER);
        uint256 tokenId = nft.mint(RECIPIENT);

        assertEq(tokenId, 1);
        assertEq(nft.ownerOf(1), RECIPIENT);
        assertEq(nft.balanceOf(RECIPIENT), 1);
    }

    function test_Mint_AssignsSequentialIds() public {
        vm.startPrank(MINTER);
        uint256 firstId = nft.mint(RECIPIENT);
        uint256 secondId = nft.mint(address(0xCAFE));
        vm.stopPrank();

        assertEq(firstId, 1);
        assertEq(secondId, 2);
        assertEq(nft.getNextTokenId(), 2);
        assertEq(nft.ownerOf(2), address(0xCAFE));
    }

    function test_Mint_Reverts_WhenCallerIsNotMinter() public {
        vm.prank(NON_MINTER);
        vm.expectRevert(abi.encodeWithSelector(HVehicleNftUnauthorizedMinter.selector, NON_MINTER));
        nft.mint(RECIPIENT);
    }

    function test_Mint_Reverts_WhenMinterIsNotSet() public {
        HenriableVehicleNFT freshNft = new HenriableVehicleNFT(address(this));

        vm.prank(MINTER);
        vm.expectRevert(abi.encodeWithSelector(HVehicleNftUnauthorizedMinter.selector, MINTER));
        freshNft.mint(RECIPIENT);
    }
}
