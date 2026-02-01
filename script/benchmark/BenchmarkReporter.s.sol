// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TestToken} from "../../src/TestToken.sol";

/// @title BenchmarkReporter - Comparative analysis of token operations
/// @notice Runs isolated benchmarks for each operation type and generates comparison report
contract BenchmarkReporter is Script {
    struct OperationMetrics {
        string name;
        uint256 txCount;
        uint256 totalGas;
        uint256 avgGas;
        uint256 minGas;
        uint256 maxGas;
        uint256 startBlock;
        uint256 endBlock;
        uint256 elapsedSeconds;
        uint256 tps;
        uint256 gasPerBlock;
    }

    struct ReportConfig {
        address tokenAddress;
        uint256 sampleSize;
        string reportDir;
    }

    ReportConfig public config;
    OperationMetrics public mintMetrics;
    OperationMetrics public transferMetrics;
    OperationMetrics public batchMintMetrics;
    OperationMetrics public burnMetrics;

    function setUp() public {
        config.tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        config.sampleSize = vm.envOr("SAMPLE_SIZE", uint256(100));
        config.reportDir = vm.envOr("REPORT_DIR", string("benchmark-results"));
    }

    function run() external {
        TestToken token = TestToken(config.tokenAddress);

        _printHeader();

        // Run isolated benchmarks for each operation
        mintMetrics = _benchmarkMintIsolated(token);
        transferMetrics = _benchmarkTransferIsolated(token);
        batchMintMetrics = _benchmarkBatchMintIsolated(token);
        burnMetrics = _benchmarkBurnIsolated(token);

        _printComparisonTable();
        _writeComparisonReport();
    }

    function _benchmarkMintIsolated(TestToken token) internal returns (OperationMetrics memory) {
        OperationMetrics memory metrics;
        metrics.name = "mint";
        metrics.minGas = type(uint256).max;
        metrics.startBlock = block.number;

        uint256 startTime = block.timestamp;

        vm.startBroadcast();

        for (uint256 i = 0; i < config.sampleSize; i++) {
            address recipient = address(uint160(uint256(keccak256(abi.encodePacked("mint_bench", i)))));

            uint256 gasStart = gasleft();
            token.mint(recipient, 1 ether);
            uint256 gasUsed = gasStart - gasleft();

            metrics.totalGas += gasUsed;
            metrics.txCount++;

            if (gasUsed < metrics.minGas) metrics.minGas = gasUsed;
            if (gasUsed > metrics.maxGas) metrics.maxGas = gasUsed;
        }

        vm.stopBroadcast();

        metrics.endBlock = block.number;
        metrics.elapsedSeconds = block.timestamp > startTime ? block.timestamp - startTime : 1;
        metrics.avgGas = metrics.totalGas / metrics.txCount;
        metrics.tps = metrics.txCount / metrics.elapsedSeconds;

        uint256 elapsedBlocks = metrics.endBlock > metrics.startBlock ? metrics.endBlock - metrics.startBlock : 1;
        metrics.gasPerBlock = metrics.totalGas / elapsedBlocks;

        console.log("Mint benchmark complete:", metrics.txCount, "txs");
        return metrics;
    }

    function _benchmarkTransferIsolated(TestToken token) internal returns (OperationMetrics memory) {
        OperationMetrics memory metrics;
        metrics.name = "transfer";
        metrics.minGas = type(uint256).max;
        metrics.startBlock = block.number;

        uint256 startTime = block.timestamp;

        // Setup: mint tokens to msg.sender for transfers
        vm.startBroadcast();
        token.mint(msg.sender, config.sampleSize * 100 ether);
        vm.stopBroadcast();

        vm.startBroadcast();

        for (uint256 i = 0; i < config.sampleSize; i++) {
            address recipient = address(uint160(uint256(keccak256(abi.encodePacked("transfer_bench", i)))));

            uint256 gasStart = gasleft();
            token.transfer(recipient, 1 ether);
            uint256 gasUsed = gasStart - gasleft();

            metrics.totalGas += gasUsed;
            metrics.txCount++;

            if (gasUsed < metrics.minGas) metrics.minGas = gasUsed;
            if (gasUsed > metrics.maxGas) metrics.maxGas = gasUsed;
        }

        vm.stopBroadcast();

        metrics.endBlock = block.number;
        metrics.elapsedSeconds = block.timestamp > startTime ? block.timestamp - startTime : 1;
        metrics.avgGas = metrics.totalGas / metrics.txCount;
        metrics.tps = metrics.txCount / metrics.elapsedSeconds;

        uint256 elapsedBlocks = metrics.endBlock > metrics.startBlock ? metrics.endBlock - metrics.startBlock : 1;
        metrics.gasPerBlock = metrics.totalGas / elapsedBlocks;

        console.log("Transfer benchmark complete:", metrics.txCount, "txs");
        return metrics;
    }

    function _benchmarkBatchMintIsolated(TestToken token) internal returns (OperationMetrics memory) {
        OperationMetrics memory metrics;
        metrics.name = "batchMint";
        metrics.minGas = type(uint256).max;
        metrics.startBlock = block.number;

        uint256 startTime = block.timestamp;

        // Test various batch sizes
        uint256[] memory batchSizes = new uint256[](5);
        batchSizes[0] = 10;
        batchSizes[1] = 25;
        batchSizes[2] = 50;
        batchSizes[3] = 75;
        batchSizes[4] = 100;

        vm.startBroadcast();

        for (uint256 b = 0; b < batchSizes.length; b++) {
            uint256 batchSize = batchSizes[b];

            address[] memory recipients = new address[](batchSize);
            uint256[] memory amounts = new uint256[](batchSize);

            for (uint256 i = 0; i < batchSize; i++) {
                recipients[i] = address(uint160(uint256(keccak256(abi.encodePacked("batch_bench", b, i)))));
                amounts[i] = 1 ether;
            }

            uint256 gasStart = gasleft();
            token.batchMint(recipients, amounts);
            uint256 gasUsed = gasStart - gasleft();

            metrics.totalGas += gasUsed;
            metrics.txCount++;

            if (gasUsed < metrics.minGas) metrics.minGas = gasUsed;
            if (gasUsed > metrics.maxGas) metrics.maxGas = gasUsed;
        }

        vm.stopBroadcast();

        metrics.endBlock = block.number;
        metrics.elapsedSeconds = block.timestamp > startTime ? block.timestamp - startTime : 1;
        metrics.avgGas = metrics.totalGas / metrics.txCount;
        metrics.tps = metrics.txCount / metrics.elapsedSeconds;

        uint256 elapsedBlocks = metrics.endBlock > metrics.startBlock ? metrics.endBlock - metrics.startBlock : 1;
        metrics.gasPerBlock = metrics.totalGas / elapsedBlocks;

        console.log("BatchMint benchmark complete:", metrics.txCount, "txs");
        return metrics;
    }

    function _benchmarkBurnIsolated(TestToken token) internal returns (OperationMetrics memory) {
        OperationMetrics memory metrics;
        metrics.name = "burn";
        metrics.minGas = type(uint256).max;
        metrics.startBlock = block.number;

        uint256 startTime = block.timestamp;

        // Setup: mint tokens to msg.sender for burning
        vm.startBroadcast();
        token.mint(msg.sender, config.sampleSize * 10 ether);
        vm.stopBroadcast();

        vm.startBroadcast();

        for (uint256 i = 0; i < config.sampleSize; i++) {
            uint256 gasStart = gasleft();
            token.burn(1 ether);
            uint256 gasUsed = gasStart - gasleft();

            metrics.totalGas += gasUsed;
            metrics.txCount++;

            if (gasUsed < metrics.minGas) metrics.minGas = gasUsed;
            if (gasUsed > metrics.maxGas) metrics.maxGas = gasUsed;
        }

        vm.stopBroadcast();

        metrics.endBlock = block.number;
        metrics.elapsedSeconds = block.timestamp > startTime ? block.timestamp - startTime : 1;
        metrics.avgGas = metrics.totalGas / metrics.txCount;
        metrics.tps = metrics.txCount / metrics.elapsedSeconds;

        uint256 elapsedBlocks = metrics.endBlock > metrics.startBlock ? metrics.endBlock - metrics.startBlock : 1;
        metrics.gasPerBlock = metrics.totalGas / elapsedBlocks;

        console.log("Burn benchmark complete:", metrics.txCount, "txs");
        return metrics;
    }

    function _printHeader() internal pure {
        console.log("");
        console.log("========================================");
        console.log("   CipherBFT Comparative Analysis");
        console.log("========================================");
        console.log("");
    }

    function _printComparisonTable() internal view {
        console.log("");
        console.log("=== OPERATION COMPARISON ===");
        console.log("");
        console.log("Operation    | Avg Gas    | Min Gas    | Max Gas    | TPS    | Gas/Block");
        console.log("-------------|------------|------------|------------|--------|----------");

        _printMetricsRow(mintMetrics);
        _printMetricsRow(transferMetrics);
        _printMetricsRow(batchMintMetrics);
        _printMetricsRow(burnMetrics);

        console.log("");

        // Find most efficient operation
        uint256 lowestAvgGas = mintMetrics.avgGas;
        string memory mostEfficient = "mint";

        if (transferMetrics.avgGas < lowestAvgGas) {
            lowestAvgGas = transferMetrics.avgGas;
            mostEfficient = "transfer";
        }
        if (burnMetrics.avgGas < lowestAvgGas) {
            lowestAvgGas = burnMetrics.avgGas;
            mostEfficient = "burn";
        }

        console.log("Most gas-efficient operation:", mostEfficient);
        console.log("");
    }

    function _printMetricsRow(OperationMetrics memory m) internal pure {
        // Foundry console.log supports max 4 params, so we format as string
        string memory row = string(abi.encodePacked(
            _padRight(m.name, 12), " | ",
            vm.toString(m.avgGas), " | ",
            vm.toString(m.minGas), " | ",
            vm.toString(m.maxGas), " | ",
            vm.toString(m.tps), " | ",
            vm.toString(m.gasPerBlock)
        ));
        console.log(row);
    }

    function _padRight(string memory s, uint256 len) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        if (b.length >= len) return s;

        bytes memory padded = new bytes(len);
        for (uint256 i = 0; i < b.length; i++) {
            padded[i] = b[i];
        }
        for (uint256 i = b.length; i < len; i++) {
            padded[i] = " ";
        }
        return string(padded);
    }

    function _writeComparisonReport() internal {
        string memory json = string(abi.encodePacked(
            '{"timestamp":', vm.toString(block.timestamp),
            ',"chainId":', vm.toString(block.chainid),
            ',"config":{"sampleSize":', vm.toString(config.sampleSize),
            ',"tokenAddress":"', vm.toString(config.tokenAddress), '"}'
        ));

        json = string(abi.encodePacked(json, ',"operations":{'));

        // Mint metrics
        json = string(abi.encodePacked(
            json, '"mint":', _metricsToJson(mintMetrics)
        ));

        // Transfer metrics
        json = string(abi.encodePacked(
            json, ',"transfer":', _metricsToJson(transferMetrics)
        ));

        // BatchMint metrics
        json = string(abi.encodePacked(
            json, ',"batchMint":', _metricsToJson(batchMintMetrics)
        ));

        // Burn metrics
        json = string(abi.encodePacked(
            json, ',"burn":', _metricsToJson(burnMetrics)
        ));

        json = string(abi.encodePacked(json, '}}'));

        string memory filename = string(abi.encodePacked(
            config.reportDir, "/comparison-", vm.toString(block.timestamp), ".json"
        ));

        vm.writeFile(filename, json);
        console.log("Comparison report saved:", filename);
    }

    function _metricsToJson(OperationMetrics memory m) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '{"txCount":', vm.toString(m.txCount),
            ',"totalGas":', vm.toString(m.totalGas),
            ',"avgGas":', vm.toString(m.avgGas),
            ',"minGas":', vm.toString(m.minGas),
            ',"maxGas":', vm.toString(m.maxGas),
            ',"tps":', vm.toString(m.tps),
            ',"gasPerBlock":', vm.toString(m.gasPerBlock), '}'
        ));
    }
}
