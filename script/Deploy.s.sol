// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TestToken} from "../src/TestToken.sol";

contract DeployToken is Script {
    function run() external returns (TestToken) {
        vm.startBroadcast();
        TestToken token = new TestToken("Test Token", "TEST");
        vm.stopBroadcast();

        console.log("Token deployed at:", address(token));
        return token;
    }
}

contract MassMint is Script {
    function run() external {
        // Configuration via environment variables
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        uint256 mintCount = vm.envOr("MINT_COUNT", uint256(100));
        uint256 mintAmount = vm.envOr("MINT_AMOUNT", uint256(1000 ether));

        TestToken token = TestToken(tokenAddress);

        console.log("Starting mass mint...");
        console.log("Token:", tokenAddress);
        console.log("Mint count:", mintCount);
        console.log("Mint amount per tx:", mintAmount);

        vm.startBroadcast();

        for (uint256 i = 0; i < mintCount; i++) {
            // Generate pseudo-random address for each mint
            address recipient = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, i)))));
            token.mint(recipient, mintAmount);
        }

        vm.stopBroadcast();

        console.log("Mass mint completed!");
        console.log("Total transactions:", mintCount);
    }
}

contract StressMint is Script {
    function run() external {
        // Stress test with configurable parameters
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        uint256 batchSize = vm.envOr("BATCH_SIZE", uint256(100));
        uint256 mintAmount = vm.envOr("MINT_AMOUNT", uint256(1 ether));

        TestToken token = TestToken(tokenAddress);

        console.log("=== Stress Test Configuration ===");
        console.log("Token:", tokenAddress);
        console.log("Batch size:", batchSize);
        console.log("Mint amount:", mintAmount);
        console.log("================================");

        vm.startBroadcast();

        // Create recipient addresses
        address[] memory recipients = new address[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            recipients[i] = address(uint160(uint256(keccak256(abi.encodePacked("recipient", i)))));
        }

        // Individual mints for maximum transaction count
        for (uint256 i = 0; i < batchSize; i++) {
            token.mint(recipients[i], mintAmount);
        }

        vm.stopBroadcast();

        console.log("Stress test completed!");
    }
}

contract ContinuousMint is Script {
    function run() external {
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        uint256 txPerRound = vm.envOr("TX_PER_ROUND", uint256(50));
        uint256 rounds = vm.envOr("ROUNDS", uint256(10));
        uint256 mintAmount = vm.envOr("MINT_AMOUNT", uint256(1 ether));

        TestToken token = TestToken(tokenAddress);

        console.log("=== Continuous Mint Test ===");
        console.log("Token:", tokenAddress);
        console.log("TX per round:", txPerRound);
        console.log("Rounds:", rounds);
        console.log("Total TX:", txPerRound * rounds);
        console.log("============================");

        for (uint256 round = 0; round < rounds; round++) {
            console.log("Round", round + 1, "of", rounds);

            vm.startBroadcast();

            for (uint256 i = 0; i < txPerRound; i++) {
                address recipient = address(
                    uint160(uint256(keccak256(abi.encodePacked("continuous", round, i))))
                );
                token.mint(recipient, mintAmount);
            }

            vm.stopBroadcast();
        }

        console.log("All rounds completed!");
    }
}
