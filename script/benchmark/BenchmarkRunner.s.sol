// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TestToken} from "../../src/TestToken.sol";

/// @title BenchmarkRunner - Core benchmark execution engine for CipherBFT
/// @notice Measures TPS and Gas Per Block for token operations
contract BenchmarkRunner is Script {
    struct BenchmarkConfig {
        address tokenAddress;
        uint256 batchSize;
        uint256 iterations;
        string reportDir;
    }

    struct BenchmarkResult {
        uint256 timestamp;
        uint256 chainId;
        uint256 startBlock;
        uint256 endBlock;
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 totalTxs;
        uint256 totalGasUsed;
        uint256 mintCount;
        uint256 mintGas;
        uint256 transferCount;
        uint256 transferGas;
        uint256 batchMintCount;
        uint256 batchMintGas;
        uint256 burnCount;
        uint256 burnGas;
    }

    BenchmarkConfig public config;
    BenchmarkResult public result;

    // Pre-generated test addresses
    address[] internal recipients;

    function setUp() public {
        config.tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        config.batchSize = vm.envOr("BATCH_SIZE", uint256(100));
        config.iterations = vm.envOr("ITERATIONS", uint256(10));
        config.reportDir = vm.envOr("REPORT_DIR", string("benchmark-results"));
    }

    function run() external {
        TestToken token = TestToken(config.tokenAddress);

        _printHeader();
        _generateRecipients();

        // Record start state
        result.timestamp = block.timestamp;
        result.chainId = block.chainid;
        result.startBlock = block.number;
        result.startTimestamp = block.timestamp;

        vm.startBroadcast();

        // Run benchmark iterations
        for (uint256 iter = 0; iter < config.iterations; iter++) {
            console.log("Iteration", iter + 1, "of", config.iterations);

            _benchmarkMint(token);
            _benchmarkTransfer(token);
            _benchmarkBatchMint(token);
            _benchmarkBurn(token);
        }

        vm.stopBroadcast();

        // Record end state
        result.endBlock = block.number;
        result.endTimestamp = block.timestamp;
        result.totalTxs = result.mintCount + result.transferCount + result.batchMintCount + result.burnCount;
        result.totalGasUsed = result.mintGas + result.transferGas + result.batchMintGas + result.burnGas;

        _printResults();
        _writeJsonReport();
    }

    function _generateRecipients() internal {
        recipients = new address[](config.batchSize);
        for (uint256 i = 0; i < config.batchSize; i++) {
            recipients[i] = address(uint160(uint256(keccak256(abi.encodePacked("benchmark_recipient", i)))));
        }
    }

    function _benchmarkMint(TestToken token) internal {
        uint256 gasStart;
        uint256 gasEnd;
        uint256 mintAmount = 1000 ether;

        for (uint256 i = 0; i < config.batchSize; i++) {
            gasStart = gasleft();
            token.mint(recipients[i], mintAmount);
            gasEnd = gasleft();

            result.mintGas += (gasStart - gasEnd);
            result.mintCount++;
        }
    }

    function _benchmarkTransfer(TestToken token) internal {
        uint256 gasStart;
        uint256 gasEnd;
        uint256 transferAmount = 100 ether;

        // Mint tokens to msg.sender first for transfer benchmark
        token.mint(msg.sender, transferAmount * config.batchSize);

        for (uint256 i = 0; i < config.batchSize; i++) {
            address to = recipients[i];

            gasStart = gasleft();
            token.transfer(to, transferAmount);
            gasEnd = gasleft();

            result.transferGas += (gasStart - gasEnd);
            result.transferCount++;
        }
    }

    function _benchmarkBatchMint(TestToken token) internal {
        uint256 gasStart;
        uint256 gasEnd;

        // Create batch arrays
        uint256 batchChunkSize = config.batchSize < 50 ? config.batchSize : 50;
        address[] memory batchRecipients = new address[](batchChunkSize);
        uint256[] memory batchAmounts = new uint256[](batchChunkSize);

        for (uint256 i = 0; i < batchChunkSize; i++) {
            batchRecipients[i] = address(uint160(uint256(keccak256(abi.encodePacked("batch_recipient", i)))));
            batchAmounts[i] = 500 ether;
        }

        gasStart = gasleft();
        token.batchMint(batchRecipients, batchAmounts);
        gasEnd = gasleft();

        result.batchMintGas += (gasStart - gasEnd);
        result.batchMintCount++;
    }

    function _benchmarkBurn(TestToken token) internal {
        uint256 gasStart;
        uint256 gasEnd;
        uint256 burnAmount = 10 ether;

        uint256 burnIterations = config.batchSize < 20 ? config.batchSize : 20;

        // Mint all tokens needed for burning upfront
        token.mint(msg.sender, burnAmount * burnIterations);

        for (uint256 i = 0; i < burnIterations; i++) {
            gasStart = gasleft();
            token.burn(burnAmount);
            gasEnd = gasleft();

            result.burnGas += (gasStart - gasEnd);
            result.burnCount++;
        }
    }

    function _printHeader() internal pure {
        console.log("");
        console.log("========================================");
        console.log("   CipherBFT Benchmark Runner");
        console.log("========================================");
        console.log("");
    }

    function _printResults() internal view {
        uint256 elapsedBlocks = result.endBlock > result.startBlock ? result.endBlock - result.startBlock : 1;
        uint256 elapsedSeconds = result.endTimestamp > result.startTimestamp ? result.endTimestamp - result.startTimestamp : 1;

        uint256 tps = result.totalTxs / elapsedSeconds;
        uint256 gasPerBlock = result.totalGasUsed / elapsedBlocks;

        console.log("");
        console.log("=== CipherBFT Benchmark Results ===");
        console.log("Chain ID:", result.chainId);
        console.log("Token:", config.tokenAddress);
        console.log("");
        console.log("Transactions:", result.totalTxs, "total");
        console.log("Blocks:", elapsedBlocks);
        console.log("Duration:", elapsedSeconds, "seconds");
        console.log("");
        console.log("-----------------------------");
        console.log("TPS:", tps, "tx/s");
        console.log("Gas/Block:", gasPerBlock);
        console.log("-----------------------------");
        console.log("");
        console.log("Operation Breakdown:");
        if (result.mintCount > 0) {
            console.log("  mint:", result.mintCount, "txs, avg gas:", result.mintGas / result.mintCount);
        }
        if (result.transferCount > 0) {
            console.log("  transfer:", result.transferCount, "txs, avg gas:", result.transferGas / result.transferCount);
        }
        if (result.batchMintCount > 0) {
            console.log("  batchMint:", result.batchMintCount, "txs, avg gas:", result.batchMintGas / result.batchMintCount);
        }
        if (result.burnCount > 0) {
            console.log("  burn:", result.burnCount, "txs, avg gas:", result.burnGas / result.burnCount);
        }
        console.log("");
    }

    function _writeJsonReport() internal {
        uint256 elapsedBlocks = result.endBlock > result.startBlock ? result.endBlock - result.startBlock : 1;
        uint256 elapsedSeconds = result.endTimestamp > result.startTimestamp ? result.endTimestamp - result.startTimestamp : 1;
        uint256 tps = result.totalTxs / elapsedSeconds;
        uint256 gasPerBlock = result.totalGasUsed / elapsedBlocks;

        string memory json = string(abi.encodePacked(
            '{"timestamp":', vm.toString(result.timestamp),
            ',"chainId":', vm.toString(result.chainId),
            ',"config":{"batchSize":', vm.toString(config.batchSize),
            ',"iterations":', vm.toString(config.iterations),
            ',"tokenAddress":"', vm.toString(config.tokenAddress), '"}'
        ));

        json = string(abi.encodePacked(
            json,
            ',"summary":{"totalTxs":', vm.toString(result.totalTxs),
            ',"totalGasUsed":', vm.toString(result.totalGasUsed),
            ',"elapsedBlocks":', vm.toString(elapsedBlocks),
            ',"elapsedSeconds":', vm.toString(elapsedSeconds),
            ',"tps":', vm.toString(tps),
            ',"gasPerBlock":', vm.toString(gasPerBlock), '}'
        ));

        json = string(abi.encodePacked(
            json,
            ',"operations":{"mint":{"count":', vm.toString(result.mintCount),
            ',"totalGas":', vm.toString(result.mintGas),
            ',"avgGas":', vm.toString(result.mintCount > 0 ? result.mintGas / result.mintCount : 0), '}'
        ));

        json = string(abi.encodePacked(
            json,
            ',"transfer":{"count":', vm.toString(result.transferCount),
            ',"totalGas":', vm.toString(result.transferGas),
            ',"avgGas":', vm.toString(result.transferCount > 0 ? result.transferGas / result.transferCount : 0), '}'
        ));

        json = string(abi.encodePacked(
            json,
            ',"batchMint":{"count":', vm.toString(result.batchMintCount),
            ',"totalGas":', vm.toString(result.batchMintGas),
            ',"avgGas":', vm.toString(result.batchMintCount > 0 ? result.batchMintGas / result.batchMintCount : 0), '}'
        ));

        json = string(abi.encodePacked(
            json,
            ',"burn":{"count":', vm.toString(result.burnCount),
            ',"totalGas":', vm.toString(result.burnGas),
            ',"avgGas":', vm.toString(result.burnCount > 0 ? result.burnGas / result.burnCount : 0), '}}}'
        ));

        string memory filename = string(abi.encodePacked(
            config.reportDir, "/benchmark-", vm.toString(result.timestamp), ".json"
        ));

        vm.writeFile(filename, json);
        console.log("Report saved:", filename);
    }
}
