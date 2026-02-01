// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {TestToken} from "../src/TestToken.sol";

contract TestTokenTest is Test {
    TestToken public token;
    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        token = new TestToken("Test Token", "TEST");
    }

    function test_InitialState() public view {
        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TEST");
        assertEq(token.totalSupply(), 0);
        assertEq(token.owner(), owner);
    }

    function test_Mint() public {
        uint256 amount = 1000 ether;

        token.mint(user1, amount);

        assertEq(token.balanceOf(user1), amount);
        assertEq(token.totalSupply(), amount);
    }

    function test_MintOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        token.mint(user2, 100 ether);
    }

    function test_BatchMint() public {
        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = makeAddr("user3");

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;
        amounts[2] = 300 ether;

        token.batchMint(recipients, amounts);

        assertEq(token.balanceOf(user1), 100 ether);
        assertEq(token.balanceOf(user2), 200 ether);
        assertEq(token.balanceOf(recipients[2]), 300 ether);
        assertEq(token.totalSupply(), 600 ether);
    }

    function test_BatchMintLengthMismatch() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](3);

        vm.expectRevert("Length mismatch");
        token.batchMint(recipients, amounts);
    }

    function test_Burn() public {
        token.mint(user1, 1000 ether);

        vm.prank(user1);
        token.burn(400 ether);

        assertEq(token.balanceOf(user1), 600 ether);
        assertEq(token.totalSupply(), 600 ether);
    }

    function test_Transfer() public {
        token.mint(user1, 1000 ether);

        vm.prank(user1);
        token.transfer(user2, 300 ether);

        assertEq(token.balanceOf(user1), 700 ether);
        assertEq(token.balanceOf(user2), 300 ether);
    }
}
