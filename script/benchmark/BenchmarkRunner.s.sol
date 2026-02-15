// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TestToken} from "../../src/TestToken.sol";

/// @notice Operation types for maxTPS measurement
enum OperationType {
    MINT,
    TRANSFER,
    BATCH_MINT,
    BURN
}

/// @title BenchmarkRunner - Core benchmark execution engine for CipherBFT
/// @notice Measures TPS and Gas Per Block for token operations
contract BenchmarkRunner is Script {
    struct BenchmarkConfig {
        address tokenAddress;
        uint256 batchSize;
        uint256 iterations;
        string reportDir;
        uint256 maxTpsInitialBatch;  // NEW
        uint256 maxTpsMaxBatch;      // NEW
        bool runMaxTps;              // NEW
    }

    /// @notice Result of a single maxTPS ramp-up round
    struct MaxTpsRoundResult {
        uint256 batchSize;
        uint256 txCount;
        uint256 gasUsed;
        uint256 elapsedBlocks;
        uint256 elapsedSeconds;
        uint256 tps;
        bool success;
    }

    /// @notice Aggregated maxTPS results for an operation type
    struct MaxTpsResult {
        uint256 maxTps;           // Highest TPS achieved
        uint256 optimalBatchSize; // Batch size that achieved maxTps
        uint256 peakGasPerBlock;  // Gas/block at max throughput
        uint256 totalTxs;         // Total transactions in successful rounds
        uint256 roundsCompleted;  // Number of ramp-up rounds tested
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

    // MaxTPS measurement results
    MaxTpsResult public mintMaxTps;
    MaxTpsResult public transferMaxTps;
    MaxTpsResult public batchMintMaxTps;
    MaxTpsResult public burnMaxTps;

    // Pre-generated test addresses
    address[] internal recipients;

    function setUp() public {
        config.tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        config.batchSize = vm.envOr("BATCH_SIZE", uint256(100));
        config.iterations = vm.envOr("ITERATIONS", uint256(10));
        config.reportDir = vm.envOr("REPORT_DIR", string("benchmark-results"));
        config.maxTpsInitialBatch = vm.envOr("MAX_TPS_INITIAL_BATCH", uint256(10));
        config.maxTpsMaxBatch = vm.envOr("MAX_TPS_MAX_BATCH", uint256(10000));
        config.runMaxTps = vm.envOr("RUN_MAX_TPS", true);
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

        // Phase 2: MaxTPS Measurement (if enabled)
        if (config.runMaxTps) {
            vm.startBroadcast();
            _runMaxTpsPhase(token);
            vm.stopBroadcast();
        }

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

    // ============================================================
    // MaxTPS Phase
    // ============================================================

    /// @notice Run maxTPS measurement phase for all operations
    function _runMaxTpsPhase(TestToken token) internal {
        console.log("");
        console.log("========================================");
        console.log("   MaxTPS Measurement Phase");
        console.log("========================================");
        console.log("");

        mintMaxTps = _measureMaxTps(token, OperationType.MINT);
        transferMaxTps = _measureMaxTps(token, OperationType.TRANSFER);
        batchMintMaxTps = _measureMaxTps(token, OperationType.BATCH_MINT);
        burnMaxTps = _measureMaxTps(token, OperationType.BURN);
    }

    /// @notice Measure maximum TPS for a specific operation type
    function _measureMaxTps(TestToken token, OperationType opType)
        internal
        returns (MaxTpsResult memory)
    {
        string memory opName;
        if (opType == OperationType.MINT) opName = "mint";
        else if (opType == OperationType.TRANSFER) opName = "transfer";
        else if (opType == OperationType.BATCH_MINT) opName = "batchMint";
        else opName = "burn";

        console.log("  Measuring maxTPS for:", opName);

        uint256 currentBatchSize = config.maxTpsInitialBatch;
        uint256 bestTps = 0;
        uint256 bestBatchSize = 0;
        uint256 bestGasPerBlock = 0;
        uint256 totalTxs = 0;
        uint256 roundsCompleted = 0;

        while (currentBatchSize <= config.maxTpsMaxBatch) {
            console.log("    Testing batch size:", currentBatchSize);

            // Generate recipients for this round
            address[] memory roundRecipients = new address[](currentBatchSize);
            for (uint256 i = 0; i < currentBatchSize; i++) {
                roundRecipients[i] = address(uint160(uint256(keccak256(abi.encodePacked("maxTps_recipient", block.timestamp, currentBatchSize, i)))));
            }

            // Record start state
            uint256 startBlock = block.number;
            uint256 startTimestamp = block.timestamp;

            // Execute batch based on operation type
            uint256 txCount;
            uint256 gasUsed;
            bool success;

            if (opType == OperationType.MINT) {
                (txCount, gasUsed, success) = _executeMintBatch(token, roundRecipients, currentBatchSize);
            } else if (opType == OperationType.TRANSFER) {
                (txCount, gasUsed, success) = _executeTransferBatch(token, roundRecipients, currentBatchSize);
            } else if (opType == OperationType.BATCH_MINT) {
                (txCount, gasUsed, success) = _executeBatchMintBatch(token, currentBatchSize);
            } else if (opType == OperationType.BURN) {
                (txCount, gasUsed, success) = _executeBurnBatch(token, currentBatchSize);
            }

            // Record end state
            uint256 endBlock = block.number;
            uint256 endTimestamp = block.timestamp;

            if (!success) {
                console.log("    FAILED at batch size:", currentBatchSize);
                break;
            }

            // Calculate metrics
            uint256 elapsedBlocks = endBlock > startBlock ? endBlock - startBlock : 1;
            uint256 elapsedSeconds = endTimestamp > startTimestamp ? endTimestamp - startTimestamp : 1;
            uint256 tps = txCount / elapsedSeconds;
            uint256 gasPerBlock = gasUsed / elapsedBlocks;

            console.log("    SUCCESS - TPS:", tps, "Gas/Block:", gasPerBlock);

            // Update best result if this round was better
            if (tps > bestTps) {
                bestTps = tps;
                bestBatchSize = currentBatchSize;
                bestGasPerBlock = gasPerBlock;
            }

            totalTxs += txCount;
            roundsCompleted++;

            // Double batch size for next round
            currentBatchSize = currentBatchSize * 2;
        }

        if (bestTps == 0) {
            console.log("  WARNING: No successful rounds for", opName);
        }

        MaxTpsResult memory maxResult;
        maxResult.maxTps = bestTps;
        maxResult.optimalBatchSize = bestBatchSize;
        maxResult.peakGasPerBlock = bestGasPerBlock;
        maxResult.totalTxs = totalTxs;
        maxResult.roundsCompleted = roundsCompleted;
        return maxResult;
    }

    // ============================================================
    // Batch Execution Helpers (for MaxTPS)
    // ============================================================

    /// @notice Execute a batch of mint operations
    function _executeMintBatch(TestToken token, address[] memory _recipients, uint256 batchSize)
        internal
        returns (uint256 txCount, uint256 gasUsed, bool success)
    {
        uint256 mintAmount = 1000 ether;

        for (uint256 i = 0; i < batchSize; i++) {
            uint256 gasStart = gasleft();
            try token.mint(_recipients[i], mintAmount) {
                uint256 gasEnd = gasleft();
                gasUsed += (gasStart - gasEnd);
                txCount++;
            } catch {
                return (txCount, gasUsed, false);
            }
        }

        return (txCount, gasUsed, true);
    }

    /// @notice Execute a batch of transfer operations
    function _executeTransferBatch(TestToken token, address[] memory _recipients, uint256 batchSize)
        internal
        returns (uint256 txCount, uint256 gasUsed, bool success)
    {
        uint256 transferAmount = 100 ether;

        // Mint tokens to msg.sender first
        token.mint(msg.sender, transferAmount * batchSize);

        for (uint256 i = 0; i < batchSize; i++) {
            uint256 gasStart = gasleft();
            try token.transfer(_recipients[i], transferAmount) {
                uint256 gasEnd = gasleft();
                gasUsed += (gasStart - gasEnd);
                txCount++;
            } catch {
                return (txCount, gasUsed, false);
            }
        }

        return (txCount, gasUsed, true);
    }

    /// @notice Execute batchMint operation
    function _executeBatchMintBatch(TestToken token, uint256 batchSize)
        internal
        returns (uint256 txCount, uint256 gasUsed, bool success)
    {
        uint256 actualBatchSize = batchSize < 50 ? batchSize : 50;
        address[] memory batchRecipients = new address[](actualBatchSize);
        uint256[] memory batchAmounts = new uint256[](actualBatchSize);

        for (uint256 i = 0; i < actualBatchSize; i++) {
            batchRecipients[i] = address(uint160(uint256(keccak256(abi.encodePacked("batch_maxTps", block.timestamp, batchSize, i)))));
            batchAmounts[i] = 500 ether;
        }

        uint256 gasStart = gasleft();
        try token.batchMint(batchRecipients, batchAmounts) {
            uint256 gasEnd = gasleft();
            gasUsed = gasStart - gasEnd;
            txCount = 1;
            return (txCount, gasUsed, true);
        } catch {
            return (0, 0, false);
        }
    }

    /// @notice Execute a batch of burn operations
    function _executeBurnBatch(TestToken token, uint256 batchSize)
        internal
        returns (uint256 txCount, uint256 gasUsed, bool success)
    {
        uint256 burnAmount = 10 ether;
        uint256 actualBurnIterations = batchSize < 20 ? batchSize : 20;

        // Mint tokens first
        token.mint(msg.sender, burnAmount * actualBurnIterations);

        for (uint256 i = 0; i < actualBurnIterations; i++) {
            uint256 gasStart = gasleft();
            try token.burn(burnAmount) {
                uint256 gasEnd = gasleft();
                gasUsed += (gasStart - gasEnd);
                txCount++;
            } catch {
                return (txCount, gasUsed, false);
            }
        }

        return (txCount, gasUsed, true);
    }

    // ============================================================
    // Display & Reporting
    // ============================================================

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

        _printMaxTpsResults();
    }

    /// @notice Print maxTPS measurement results to console
    function _printMaxTpsResults() internal view {
        if (!config.runMaxTps) {
            return;
        }

        console.log("=== MaxTPS Results ===");
        console.log("");

        if (mintMaxTps.maxTps > 0) {
            console.log("mint:");
            console.log("  Max TPS:", mintMaxTps.maxTps, "tx/s");
            console.log("  Optimal Batch:", mintMaxTps.optimalBatchSize);
            console.log("  Peak Gas/Block:", mintMaxTps.peakGasPerBlock);
            console.log("  Rounds Completed:", mintMaxTps.roundsCompleted);
            console.log("");
        }

        if (transferMaxTps.maxTps > 0) {
            console.log("transfer:");
            console.log("  Max TPS:", transferMaxTps.maxTps, "tx/s");
            console.log("  Optimal Batch:", transferMaxTps.optimalBatchSize);
            console.log("  Peak Gas/Block:", transferMaxTps.peakGasPerBlock);
            console.log("  Rounds Completed:", transferMaxTps.roundsCompleted);
            console.log("");
        }

        if (batchMintMaxTps.maxTps > 0) {
            console.log("batchMint:");
            console.log("  Max TPS:", batchMintMaxTps.maxTps, "tx/s");
            console.log("  Optimal Batch:", batchMintMaxTps.optimalBatchSize);
            console.log("  Peak Gas/Block:", batchMintMaxTps.peakGasPerBlock);
            console.log("  Rounds Completed:", batchMintMaxTps.roundsCompleted);
            console.log("");
        }

        if (burnMaxTps.maxTps > 0) {
            console.log("burn:");
            console.log("  Max TPS:", burnMaxTps.maxTps, "tx/s");
            console.log("  Optimal Batch:", burnMaxTps.optimalBatchSize);
            console.log("  Peak Gas/Block:", burnMaxTps.peakGasPerBlock);
            console.log("  Rounds Completed:", burnMaxTps.roundsCompleted);
            console.log("");
        }
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
            ',"tokenAddress":"', vm.toString(config.tokenAddress), '"',
            ',"maxTpsInitialBatch":', vm.toString(config.maxTpsInitialBatch),
            ',"maxTpsMaxBatch":', vm.toString(config.maxTpsMaxBatch),
            ',"runMaxTps":', config.runMaxTps ? '"true"' : '"false"', '}'
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
            ',"avgGas":', vm.toString(result.burnCount > 0 ? result.burnGas / result.burnCount : 0), '}}'
        ));

        // Add maxTPS section
        string memory maxTpsJson = _buildMaxTpsJson();
        json = string(abi.encodePacked(json, maxTpsJson, '}'));

        string memory filename = string(abi.encodePacked(
            config.reportDir, "/benchmark-", vm.toString(result.timestamp), ".json"
        ));

        vm.writeFile(filename, json);
        console.log("Report saved:", filename);
    }

    /// @notice Build JSON string for maxTPS results
    function _buildMaxTpsJson() internal view returns (string memory) {
        if (!config.runMaxTps) {
            return "";
        }

        string memory json = ',"maxTps":{';

        // Mint
        json = string(abi.encodePacked(
            json,
            '"mint":{"maxTps":', vm.toString(mintMaxTps.maxTps),
            ',"optimalBatchSize":', vm.toString(mintMaxTps.optimalBatchSize),
            ',"peakGasPerBlock":', vm.toString(mintMaxTps.peakGasPerBlock),
            ',"totalTxs":', vm.toString(mintMaxTps.totalTxs),
            ',"roundsCompleted":', vm.toString(mintMaxTps.roundsCompleted), '}'
        ));

        // Transfer
        json = string(abi.encodePacked(
            json,
            ',"transfer":{"maxTps":', vm.toString(transferMaxTps.maxTps),
            ',"optimalBatchSize":', vm.toString(transferMaxTps.optimalBatchSize),
            ',"peakGasPerBlock":', vm.toString(transferMaxTps.peakGasPerBlock),
            ',"totalTxs":', vm.toString(transferMaxTps.totalTxs),
            ',"roundsCompleted":', vm.toString(transferMaxTps.roundsCompleted), '}'
        ));

        // BatchMint
        json = string(abi.encodePacked(
            json,
            ',"batchMint":{"maxTps":', vm.toString(batchMintMaxTps.maxTps),
            ',"optimalBatchSize":', vm.toString(batchMintMaxTps.optimalBatchSize),
            ',"peakGasPerBlock":', vm.toString(batchMintMaxTps.peakGasPerBlock),
            ',"totalTxs":', vm.toString(batchMintMaxTps.totalTxs),
            ',"roundsCompleted":', vm.toString(batchMintMaxTps.roundsCompleted), '}'
        ));

        // Burn
        json = string(abi.encodePacked(
            json,
            ',"burn":{"maxTps":', vm.toString(burnMaxTps.maxTps),
            ',"optimalBatchSize":', vm.toString(burnMaxTps.optimalBatchSize),
            ',"peakGasPerBlock":', vm.toString(burnMaxTps.peakGasPerBlock),
            ',"totalTxs":', vm.toString(burnMaxTps.totalTxs),
            ',"roundsCompleted":', vm.toString(burnMaxTps.roundsCompleted), '}}'
        ));

        return json;
    }
}
