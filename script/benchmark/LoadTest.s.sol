// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TestToken} from "../../src/TestToken.sol";

/// @title LoadTest - Find maximum sustainable TPS for CipherBFT
/// @notice Ramps up transaction rate until failures occur
contract LoadTest is Script {
    struct LoadTestConfig {
        address tokenAddress;
        uint256 initialBatchSize;
        uint256 maxBatchSize;
        uint256 txPerTest;
        string reportDir;
    }

    struct RoundResult {
        uint256 batchSize;
        uint256 txCount;
        uint256 gasUsed;
        uint256 startBlock;
        uint256 endBlock;
        uint256 startTimestamp;
        uint256 endTimestamp;
        bool success;
    }

    LoadTestConfig public config;
    RoundResult[] public rounds;

    uint256 public maxSustainableTps;
    uint256 public optimalBatchSize;
    uint256 public peakGasPerBlock;

    function setUp() public {
        config.tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        config.initialBatchSize = vm.envOr("INITIAL_BATCH_SIZE", uint256(10));
        config.maxBatchSize = vm.envOr("MAX_BATCH_SIZE", uint256(1000));
        config.txPerTest = vm.envOr("TX_PER_TEST", uint256(100));
        config.reportDir = vm.envOr("REPORT_DIR", string("benchmark-results"));
    }

    function run() external {
        TestToken token = TestToken(config.tokenAddress);

        _printHeader();

        uint256 currentBatchSize = config.initialBatchSize;
        bool continueRamping = true;

        while (continueRamping && currentBatchSize <= config.maxBatchSize) {
            console.log("");
            console.log("Testing batch size:", currentBatchSize);

            RoundResult memory roundResult = _runLoadRound(token, currentBatchSize);
            rounds.push(roundResult);

            if (roundResult.success) {
                uint256 elapsedSeconds = roundResult.endTimestamp > roundResult.startTimestamp
                    ? roundResult.endTimestamp - roundResult.startTimestamp
                    : 1;
                uint256 tps = roundResult.txCount / elapsedSeconds;

                uint256 elapsedBlocks = roundResult.endBlock > roundResult.startBlock
                    ? roundResult.endBlock - roundResult.startBlock
                    : 1;
                uint256 gasPerBlock = roundResult.gasUsed / elapsedBlocks;

                console.log("  Success! TPS:", tps, "| Gas/Block:", gasPerBlock);

                if (tps > maxSustainableTps) {
                    maxSustainableTps = tps;
                    optimalBatchSize = currentBatchSize;
                    peakGasPerBlock = gasPerBlock;
                }

                // Double batch size for next round
                currentBatchSize = currentBatchSize * 2;
            } else {
                console.log("  Failed at batch size:", currentBatchSize);
                continueRamping = false;
            }
        }

        _printFinalResults();
        _writeJsonReport();
    }

    function _runLoadRound(TestToken token, uint256 batchSize) internal returns (RoundResult memory) {
        RoundResult memory roundResult;
        roundResult.batchSize = batchSize;
        roundResult.startBlock = block.number;
        roundResult.startTimestamp = block.timestamp;

        uint256 totalGas = 0;
        uint256 txCount = 0;

        vm.startBroadcast();

        // Generate recipients for this round
        address[] memory recipients = new address[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            recipients[i] = address(uint160(uint256(keccak256(abi.encodePacked("load_test", block.timestamp, i)))));
        }

        // Execute transactions
        uint256 iterations = config.txPerTest / batchSize;
        if (iterations == 0) iterations = 1;

        for (uint256 iter = 0; iter < iterations; iter++) {
            for (uint256 i = 0; i < batchSize; i++) {
                uint256 gasStart = gasleft();

                try token.mint(recipients[i], 1 ether) {
                    uint256 gasEnd = gasleft();
                    totalGas += (gasStart - gasEnd);
                    txCount++;
                } catch {
                    // Transaction failed, mark round as failed
                    vm.stopBroadcast();
                    roundResult.success = false;
                    roundResult.endBlock = block.number;
                    roundResult.endTimestamp = block.timestamp;
                    roundResult.txCount = txCount;
                    roundResult.gasUsed = totalGas;
                    return roundResult;
                }
            }
        }

        vm.stopBroadcast();

        roundResult.success = true;
        roundResult.endBlock = block.number;
        roundResult.endTimestamp = block.timestamp;
        roundResult.txCount = txCount;
        roundResult.gasUsed = totalGas;

        return roundResult;
    }

    function _printHeader() internal pure {
        console.log("");
        console.log("========================================");
        console.log("   CipherBFT Load Test");
        console.log("   Finding Maximum Sustainable TPS");
        console.log("========================================");
    }

    function _printFinalResults() internal view {
        console.log("");
        console.log("========================================");
        console.log("   LOAD TEST COMPLETE");
        console.log("========================================");
        console.log("");
        console.log("Maximum Sustainable TPS:", maxSustainableTps);
        console.log("Optimal Batch Size:", optimalBatchSize);
        console.log("Peak Gas/Block:", peakGasPerBlock);
        console.log("");
        console.log("Rounds completed:", rounds.length);

        for (uint256 i = 0; i < rounds.length; i++) {
            RoundResult memory r = rounds[i];
            string memory status = r.success ? "PASS" : "FAIL";
            console.log("  Round", i + 1);
            console.log("    Batch:", r.batchSize, "Status:", status);
        }
        console.log("");
    }

    function _writeJsonReport() internal {
        string memory json = string(abi.encodePacked(
            '{"timestamp":', vm.toString(block.timestamp),
            ',"chainId":', vm.toString(block.chainid),
            ',"config":{"initialBatchSize":', vm.toString(config.initialBatchSize),
            ',"maxBatchSize":', vm.toString(config.maxBatchSize),
            ',"txPerTest":', vm.toString(config.txPerTest),
            ',"tokenAddress":"', vm.toString(config.tokenAddress), '"}'
        ));

        json = string(abi.encodePacked(
            json,
            ',"results":{"maxSustainableTps":', vm.toString(maxSustainableTps),
            ',"optimalBatchSize":', vm.toString(optimalBatchSize),
            ',"peakGasPerBlock":', vm.toString(peakGasPerBlock),
            ',"roundsCompleted":', vm.toString(rounds.length), '}'
        ));

        // Add rounds array
        json = string(abi.encodePacked(json, ',"rounds":['));

        for (uint256 i = 0; i < rounds.length; i++) {
            RoundResult memory r = rounds[i];
            if (i > 0) {
                json = string(abi.encodePacked(json, ','));
            }
            json = string(abi.encodePacked(
                json,
                '{"batchSize":', vm.toString(r.batchSize),
                ',"txCount":', vm.toString(r.txCount),
                ',"gasUsed":', vm.toString(r.gasUsed),
                ',"success":', r.success ? 'true' : 'false', '}'
            ));
        }

        json = string(abi.encodePacked(json, ']}'));

        string memory filename = string(abi.encodePacked(
            config.reportDir, "/loadtest-", vm.toString(block.timestamp), ".json"
        ));

        vm.writeFile(filename, json);
        console.log("Report saved:", filename);
    }
}
