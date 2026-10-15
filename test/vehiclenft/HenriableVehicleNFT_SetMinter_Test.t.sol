// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {HVehicleNftUnauthorizedMinter} from "../../src/types/common.sol";
import {HenriableVehicleNFT} from "../../src/HenriableVehicleNFT.sol";

/// @title Tests for {HenriableVehicleNFT.setMinter}.
/// @notice Only the collection owner may set the minter, and setting it changes who is allowed
///         to mint (address(0) disables minting).
contract HenriableVehicleNFTSetMinterTest is Test {
    address internal constant MINTER = address(0x1111);
    address internal constant OTHER_MINTER = address(0x2222);
    address internal constant NON_OWNER = address(0xDEAD);
    address internal constant RECIPIENT = address(0xB0B);

    HenriableVehicleNFT internal nft;

    function setUp() public {
        nft = new HenriableVehicleNFT(address(this));
    }

    function test_SetMinter_UpdatesMinter() public {
        nft.setMinter(MINTER);

        assertEq(nft.getMinter(), MINTER);
    }

    function test_SetMinter_ChangesWhoCanMint() public {
        nft.setMinter(MINTER);
        nft.setMinter(OTHER_MINTER);

        // The old minter loses the right and the new one gains it.
        vm.prank(MINTER);
        vm.expectRevert(abi.encodeWithSelector(HVehicleNftUnauthorizedMinter.selector, MINTER));
        nft.mint(RECIPIENT);

        vm.prank(OTHER_MINTER);
        assertEq(nft.mint(RECIPIENT), 1);
    }

    function test_SetMinter_DisablesMinting_WhenSetToZero() public {
        nft.setMinter(MINTER);
        nft.setMinter(address(0));

        assertEq(nft.getMinter(), address(0));

        vm.prank(MINTER);
        vm.expectRevert(abi.encodeWithSelector(HVehicleNftUnauthorizedMinter.selector, MINTER));
        nft.mint(RECIPIENT);
    }

    function test_SetMinter_Reverts_WhenCallerIsNotOwner() public {
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        nft.setMinter(MINTER);
    }
}
