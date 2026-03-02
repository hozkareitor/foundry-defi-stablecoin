// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { Test } from "forge-std/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

contract DecentralizedStableCoinTest is StdCheats, Test {
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    DecentralizedStableCoin dsc;
    address owner;
    address user = address(1);
    address nonOwner = address(2);

    function setUp() public {
        owner = makeAddr("owner");
        dsc = new DecentralizedStableCoin(owner);
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////  
    
    function test_ConstructorSetsOwner() public view {
        assertEq(dsc.owner(), owner);
    }

    function test_ConstructorSetsNameAndSymbol() public view {
        assertEq(dsc.name(), "DecentralizedStableCoin");
        assertEq(dsc.symbol(), "DSC");
    }

    function test_RevertWhen_ConstructorWithZeroAddress() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableInvalidOwner(address)", address(0)));
        new DecentralizedStableCoin(address(0));
    }

    ///////////////////////
    //    Mint Tests     //
    ///////////////////////  

    function test_RevertWhen_MintAmountIsZero() public {
        vm.prank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeGreaterThanZero.selector);
        dsc.mint(user, 0);
    }

    function test_RevertWhen_MintToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__ZeroAddressNotAllowed.selector);
        dsc.mint(address(0), 100 ether);
    }

    function test_RevertWhen_NonOwnerMints() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        dsc.mint(user, 100 ether);
    }

    function test_MintSuccess() public {
        vm.prank(owner);
        bool success = dsc.mint(user, 100 ether);
        
        assertTrue(success);
        assertEq(dsc.balanceOf(user), 100 ether);
        assertEq(dsc.totalSupply(), 100 ether);
    }

    function test_MintEmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true, address(dsc));
        emit Mint(user, 100 ether);
        dsc.mint(user, 100 ether);
    }

    function test_MintMultipleTimes() public {
        vm.startPrank(owner);
        dsc.mint(user, 50 ether);
        dsc.mint(user, 30 ether);
        vm.stopPrank();
        
        assertEq(dsc.balanceOf(user), 80 ether);
        assertEq(dsc.totalSupply(), 80 ether);
    }

    function test_MintToDifferentAddresses() public {
        address user2 = makeAddr("user2");
        
        vm.startPrank(owner);
        dsc.mint(user, 50 ether);
        dsc.mint(user2, 30 ether);
        vm.stopPrank();
        
        assertEq(dsc.balanceOf(user), 50 ether);
        assertEq(dsc.balanceOf(user2), 30 ether);
        assertEq(dsc.totalSupply(), 80 ether);
    }

    ///////////////////////
    //    Burn Tests     //
    /////////////////////// 

    function test_RevertWhen_BurnAmountIsZero() public {
        vm.prank(owner);
        dsc.mint(owner, 100 ether);  // Mint to owner
        
        vm.prank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeGreaterThanZero.selector);
        dsc.burn(0);
    }

    function test_RevertWhen_BurnAmountExceedsBalance() public {
        vm.prank(owner);
        dsc.mint(owner, 100 ether);  // Mint to owner
        
        vm.prank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(101 ether);
    }

    function test_RevertWhen_NonOwnerBurns() public {
        vm.prank(owner);
        dsc.mint(owner, 100 ether);
        
        vm.prank(nonOwner);
        vm.expectRevert();
        dsc.burn(50 ether);
    }

    function test_BurnSuccess() public {
        vm.prank(owner);
        dsc.mint(owner, 100 ether);  // Mint to owner
        
        vm.prank(owner);
        dsc.burn(40 ether);
        
        assertEq(dsc.balanceOf(owner), 60 ether);
        assertEq(dsc.totalSupply(), 60 ether);
    }

    function test_BurnEmitsEvent() public {
        vm.prank(owner);
        dsc.mint(owner, 100 ether);  // Mint to owner
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true, address(dsc));
        emit Burn(owner, 40 ether);  // From owner, not user
        dsc.burn(40 ether);
    }

    function test_BurnAllTokens() public {
        vm.prank(owner);
        dsc.mint(owner, 100 ether);  // Mint to owner
        
        vm.prank(owner);
        dsc.burn(100 ether);
        
        assertEq(dsc.balanceOf(owner), 0);
        assertEq(dsc.totalSupply(), 0);
    }

    function test_BurnAfterMultipleMints() public {
        vm.startPrank(owner);
        dsc.mint(owner, 50 ether);
        dsc.mint(owner, 30 ether);
        vm.stopPrank();
        
        vm.prank(owner);
        dsc.burn(20 ether);
        
        assertEq(dsc.balanceOf(owner), 60 ether);
        assertEq(dsc.totalSupply(), 60 ether);
    }

    function test_BurnAfterMaxMint() public {
        vm.prank(owner);
        uint256 maxAmount = type(uint256).max;
        dsc.mint(owner, maxAmount);  // Mint to owner
        
        vm.prank(owner);
        dsc.burn(maxAmount);
        
        assertEq(dsc.balanceOf(owner), 0);
        assertEq(dsc.totalSupply(), 0);
    }

    ///////////////////////////
    // ERC20 Standard  Tests //
    ///////////////////////////

    function test_Transfer() public {
        address user2 = makeAddr("user2");
        
        vm.prank(owner);
        dsc.mint(user, 100 ether);
        
        vm.prank(user);
        dsc.transfer(user2, 30 ether);
        
        assertEq(dsc.balanceOf(user), 70 ether);
        assertEq(dsc.balanceOf(user2), 30 ether);
    }

    function test_ApproveAndTransferFrom() public {
        address spender = makeAddr("spender");
        address user2 = makeAddr("user2");
        
        vm.prank(owner);
        dsc.mint(user, 100 ether);
        
        vm.prank(user);
        dsc.approve(spender, 50 ether);
        
        vm.prank(spender);
        dsc.transferFrom(user, user2, 30 ether);
        
        assertEq(dsc.balanceOf(user), 70 ether);
        assertEq(dsc.balanceOf(user2), 30 ether);
        assertEq(dsc.allowance(user, spender), 20 ether);
    }

    ///////////////////////
    //  Owner Functions  //
    ///////////////////////

    function test_TransferOwnership() public {
        address newOwner = makeAddr("newOwner");
        
        vm.prank(owner);
        dsc.transferOwnership(newOwner);
        
        assertEq(dsc.owner(), newOwner);
    }

    function test_RevertWhen_NonOwnerTransfersOwnership() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        dsc.transferOwnership(nonOwner);
    }

    function test_RevertWhen_TransferOwnershipToZeroAddress() public {
        vm.prank(owner);
        // OZ's ownable already validates address zero with its own error
        vm.expectRevert(abi.encodeWithSignature("OwnableInvalidOwner(address)", address(0)));
        dsc.transferOwnership(address(0));
    }

    function test_TransferOwnershipEmitsEvent() public {
        address newOwner = makeAddr("newOwner");
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true, address(dsc));
        emit OwnershipTransferred(owner, newOwner);
        dsc.transferOwnership(newOwner);
    }

    ///////////////////////////
    //  Decay Functions      //
    ///////////////////////////

    function test_Decimals() public view {
        assertEq(dsc.decimals(), 18);
    }
}