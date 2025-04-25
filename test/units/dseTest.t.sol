// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { DeployDSC } from "script/DeployDSC.s.sol";
import { DecentralisedStablecoin } from "src/DecentralisedStablecoin.sol";

contract dscTest is Test {
    DecentralisedStablecoin dsc;
    DeployDSC deployer;

    address public USER = makeAddr("user");
    address public owner;

    uint256 private constant MINT_AMOUNT = 100e18;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc,,) = deployer.run();

        owner = address(dsc.owner());
    }

    function testMint() public {
        vm.startPrank(owner);
        dsc.mint(USER, MINT_AMOUNT);
        assertEq(dsc.balanceOf(USER), MINT_AMOUNT); 
        vm.stopPrank();
    }

    function testMintFafilsIfAmountIsLessThanZero() public {
        vm.startPrank(owner);
        vm.expectRevert(DecentralisedStablecoin.DecentralisedStablecoin__AmountMustBeGreaterThanZero.selector);
        dsc.mint(USER, 0);
        vm.stopPrank();
    }

    function testMintFafilsIfAddressIsInvalid() public {
        vm.startPrank(owner);
        vm.expectRevert(DecentralisedStablecoin.DecentralisedStablecoin__AddressNotValid.selector);
        dsc.mint(address(0x0), 0);
        vm.stopPrank();
    }

    function testBurn() public {
        vm.startPrank(owner);
        dsc.mint(USER, MINT_AMOUNT);
        vm.stopPrank();
        vm.startPrank(USER);
        dsc.burn(MINT_AMOUNT);
        assertEq(dsc.balanceOf(USER), 0); 
        vm.stopPrank();
    }

    function testBurnFafilsIfAmountIsLessThanZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DecentralisedStablecoin.DecentralisedStablecoin__AmountMustBeGreaterThanZero.selector);
        dsc.burn(0);
        vm.stopPrank();
    }

    function testBurnFafilsIfBalanceIsLessThanAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(DecentralisedStablecoin.DecentralisedStablecoin__InsufficientBalance.selector);
        dsc.burn(MINT_AMOUNT);
        vm.stopPrank();
    }
}