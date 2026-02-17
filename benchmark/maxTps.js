const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

// ============================================================
// Configuration
// ============================================================

const CONFIG = {
  rpcUrl: process.env.RPC_URL || "http://localhost:8545",
  privateKey:
    process.env.PRIVATE_KEY ||
    "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
  tokenAddress: process.env.TOKEN_ADDRESS,
  initialBatch: parseInt(process.env.INITIAL_BATCH || "10"),
  maxBatch: parseInt(process.env.MAX_BATCH || "10000"),
  roundTimeout: parseInt(process.env.ROUND_TIMEOUT || "60000"),
  failureThreshold: parseFloat(process.env.FAILURE_THRESHOLD || "0.1"),
  reportDir: process.env.REPORT_DIR || "benchmark-results",
  gasLimit: 500_000,
  mintAmount: ethers.parseEther("1000"),
  transferAmount: ethers.parseEther("100"),
  burnAmount: ethers.parseEther("10"),
  batchMintChunkSize: 50,
};

// ============================================================
// ABI Loading
// ============================================================

function loadABI() {
  const foundryPath = path.resolve(
    __dirname,
    "../out/TestToken.sol/TestToken.json"
  );
  if (fs.existsSync(foundryPath)) {
    const artifact = JSON.parse(fs.readFileSync(foundryPath, "utf8"));
    return artifact.abi;
  }
  // Fallback: human-readable ABI
  return [
    "function mint(address to, uint256 amount) external",
    "function transfer(address to, uint256 value) external returns (bool)",
    "function batchMint(address[] recipients, uint256[] amounts) external",
    "function burn(uint256 amount) external",
    "function balanceOf(address account) external view returns (uint256)",
    "function owner() external view returns (address)",
  ];
}

// ============================================================
// Utilities
// ============================================================

function generateAddress(seed) {
  const hash = ethers.keccak256(ethers.toUtf8Bytes(seed));
  return ethers.getAddress("0x" + hash.slice(26));
}

function timeoutPromise(ms) {
  return new Promise((_, reject) =>
    setTimeout(() => reject(new Error("timeout")), ms)
  );
}

// ============================================================
// Setup (not timed)
// ============================================================

async function setupForOperation(token, wallet, operationType, batchSize) {
  if (operationType === "transfer") {
    const needed = CONFIG.transferAmount * BigInt(batchSize);
    const balance = await token.balanceOf(wallet.address);
    if (balance < needed) {
      const toMint = needed - balance + CONFIG.transferAmount;
      const tx = await token.mint(wallet.address, toMint);
      await tx.wait();
    }
  } else if (operationType === "burn") {
    const needed = CONFIG.burnAmount * BigInt(batchSize);
    const balance = await token.balanceOf(wallet.address);
    if (balance < needed) {
      const toMint = needed - balance + CONFIG.burnAmount;
      const tx = await token.mint(wallet.address, toMint);
      await tx.wait();
    }
  }
}

// ============================================================
// Transaction Builders
// ============================================================

function buildOperationTx(token, operationType, index, nonce) {
  const opts = { nonce, gasLimit: CONFIG.gasLimit };

  switch (operationType) {
    case "mint": {
      const recipient = generateAddress(`maxTps_mint_${Date.now()}_${index}`);
      return token.mint.populateTransaction(
        recipient,
        CONFIG.mintAmount,
        opts
      );
    }
    case "transfer": {
      const recipient = generateAddress(
        `maxTps_transfer_${Date.now()}_${index}`
      );
      return token.transfer.populateTransaction(
        recipient,
        CONFIG.transferAmount,
        opts
      );
    }
    case "batchMint": {
      const recipients = [];
      const amounts = [];
      const chunkSize = Math.min(CONFIG.batchMintChunkSize, 50);
      for (let j = 0; j < chunkSize; j++) {
        recipients.push(
          generateAddress(`batch_${Date.now()}_${index}_${j}`)
        );
        amounts.push(ethers.parseEther("500"));
      }
      return token.batchMint.populateTransaction(
        recipients,
        amounts,
        opts
      );
    }
    case "burn": {
      return token.burn.populateTransaction(CONFIG.burnAmount, opts);
    }
    default:
      throw new Error(`Unknown operation: ${operationType}`);
  }
}

// ============================================================
// Core: Execute a Single Round
// ============================================================

async function executeRound(
  token,
  wallet,
  provider,
  operationType,
  batchSize
) {
  const baseNonce = await provider.getTransactionCount(
    wallet.address,
    "pending"
  );

  // Build all transaction data
  const txDataArr = [];
  for (let i = 0; i < batchSize; i++) {
    txDataArr.push(
      await buildOperationTx(token, operationType, i, baseNonce + i)
    );
  }

  // ---- WALL CLOCK START ----
  const startTime = Date.now();
  const startBlock = await provider.getBlockNumber();

  // Send all transactions in parallel
  const sendPromises = txDataArr.map((txData) =>
    wallet.sendTransaction(txData)
  );
  const sendResults = await Promise.allSettled(sendPromises);

  // Collect successfully sent transactions
  const sentTxs = [];
  let sendFailures = 0;
  for (const r of sendResults) {
    if (r.status === "fulfilled" && r.value) {
      sentTxs.push(r.value);
    } else {
      sendFailures++;
    }
  }

  // Check if too many sends failed
  if (sendFailures / batchSize > CONFIG.failureThreshold) {
    const endTime = Date.now();
    return {
      success: false,
      reason: `${sendFailures}/${batchSize} sends failed`,
      batchSize,
      txCount: sentTxs.length,
      totalGas: 0,
      gasPerBlock: 0,
      elapsedMs: endTime - startTime,
      sendFailures,
      revertCount: 0,
    };
  }

  // Wait for all receipts with timeout
  const receiptPromises = sentTxs.map((tx) =>
    Promise.race([tx.wait(), timeoutPromise(CONFIG.roundTimeout)])
  );
  const receiptResults = await Promise.allSettled(receiptPromises);

  // ---- WALL CLOCK END ----
  const endTime = Date.now();
  const endBlock = await provider.getBlockNumber();

  // Process receipts
  let confirmedCount = 0;
  let totalGas = 0n;
  let revertCount = 0;

  for (const r of receiptResults) {
    if (r.status === "fulfilled" && r.value) {
      const receipt = r.value;
      if (receipt.status === 1) {
        confirmedCount++;
        totalGas += receipt.gasUsed;
      } else {
        revertCount++;
      }
    }
  }

  const failureRate = (batchSize - confirmedCount) / batchSize;
  const success = failureRate <= CONFIG.failureThreshold;
  const elapsedMs = endTime - startTime;
  const elapsedBlocks =
    endBlock > startBlock ? endBlock - startBlock : 1;
  const gasPerBlock = Number(totalGas / BigInt(elapsedBlocks));

  return {
    success,
    batchSize,
    txCount: confirmedCount,
    totalGas: Number(totalGas),
    gasPerBlock,
    elapsedMs,
    startBlock,
    endBlock,
    sendFailures,
    revertCount,
  };
}

// ============================================================
// Core: Ramp-up MaxTPS Measurement
// ============================================================

async function measureMaxTps(token, wallet, provider, operationType) {
  let currentBatch = CONFIG.initialBatch;
  let bestTps = 0;
  let bestBatchSize = 0;
  let bestGasPerBlock = 0;
  let totalTxs = 0;
  let roundsCompleted = 0;
  const rounds = [];

  while (currentBatch <= CONFIG.maxBatch) {
    console.log(`    Testing batch size: ${currentBatch}`);

    // Setup (not timed)
    await setupForOperation(token, wallet, operationType, currentBatch);

    // Execute round (timed)
    const roundResult = await executeRound(
      token,
      wallet,
      provider,
      operationType,
      currentBatch
    );
    rounds.push(roundResult);

    if (!roundResult.success) {
      console.log(
        `    FAILED at batch size: ${currentBatch} (${roundResult.reason || "reverts/timeouts"})`
      );
      break;
    }

    const tps = roundResult.txCount / (roundResult.elapsedMs / 1000);
    console.log(
      `    SUCCESS - ${roundResult.txCount} txs in ${roundResult.elapsedMs}ms = ${tps.toFixed(1)} TPS, Gas/Block: ${roundResult.gasPerBlock}`
    );

    if (tps > bestTps) {
      bestTps = tps;
      bestBatchSize = currentBatch;
      bestGasPerBlock = roundResult.gasPerBlock;
    }

    totalTxs += roundResult.txCount;
    roundsCompleted++;

    // Double batch size for next round
    currentBatch *= 2;
  }

  return {
    maxTps: Math.round(bestTps),
    optimalBatchSize: bestBatchSize,
    peakGasPerBlock: bestGasPerBlock,
    totalTxs,
    roundsCompleted,
    rounds: rounds.map((r) => ({
      batchSize: r.batchSize,
      txCount: r.txCount,
      totalGas: r.totalGas,
      elapsedMs: r.elapsedMs,
      tps: r.elapsedMs > 0 ? r.txCount / (r.elapsedMs / 1000) : 0,
      success: r.success,
    })),
  };
}

// ============================================================
// Reporting
// ============================================================

function printResults(results) {
  console.log("\n========================================");
  console.log("   MaxTPS Results (Wall-Clock)");
  console.log("========================================\n");

  for (const [op, r] of Object.entries(results)) {
    if (r.maxTps > 0) {
      console.log(`${op}:`);
      console.log(`  Max TPS:         ${r.maxTps} tx/s`);
      console.log(`  Optimal Batch:   ${r.optimalBatchSize}`);
      console.log(`  Peak Gas/Block:  ${r.peakGasPerBlock}`);
      console.log(`  Total Txs:       ${r.totalTxs}`);
      console.log(`  Rounds:          ${r.roundsCompleted}`);
      console.log();
    } else {
      console.log(`${op}: No successful rounds`);
      console.log();
    }
  }
}

function buildReport(results, chainId) {
  return {
    timestamp: Math.floor(Date.now() / 1000),
    chainId,
    tool: "node-maxTps",
    config: {
      initialBatch: CONFIG.initialBatch,
      maxBatch: CONFIG.maxBatch,
      roundTimeoutMs: CONFIG.roundTimeout,
      failureThreshold: CONFIG.failureThreshold,
      tokenAddress: CONFIG.tokenAddress,
    },
    maxTps: {
      mint: results.mint,
      transfer: results.transfer,
      batchMint: results.batchMint,
      burn: results.burn,
    },
  };
}

// ============================================================
// Main
// ============================================================

async function main() {
  if (!CONFIG.tokenAddress) {
    console.error("ERROR: TOKEN_ADDRESS environment variable is required");
    console.error(
      "Usage: TOKEN_ADDRESS=0x... node maxTps.js"
    );
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(CONFIG.rpcUrl);
  const wallet = new ethers.Wallet(CONFIG.privateKey, provider);
  const abi = loadABI();
  const token = new ethers.Contract(CONFIG.tokenAddress, abi, wallet);

  // Verify connectivity
  const network = await provider.getNetwork();
  console.log(`Connected to chain ${network.chainId}`);
  console.log(`Wallet: ${wallet.address}`);
  console.log(`Token:  ${CONFIG.tokenAddress}`);

  // Verify ownership
  try {
    const owner = await token.owner();
    if (owner.toLowerCase() !== wallet.address.toLowerCase()) {
      console.warn(
        `WARNING: Wallet is not token owner. mint/batchMint will fail.`
      );
    }
  } catch {
    console.warn("WARNING: Could not verify token ownership.");
  }

  console.log("\n========================================");
  console.log("   CipherBFT MaxTPS Benchmark (Node.js)");
  console.log("========================================");
  console.log(
    `Config: initialBatch=${CONFIG.initialBatch}, maxBatch=${CONFIG.maxBatch}, timeout=${CONFIG.roundTimeout}ms`
  );

  const operations = ["mint", "transfer", "batchMint", "burn"];
  const results = {};

  for (const op of operations) {
    console.log(`\n  Measuring maxTPS for: ${op}`);
    results[op] = await measureMaxTps(token, wallet, provider, op);
  }

  // Print summary
  printResults(results);

  // Write JSON report
  const report = buildReport(results, Number(network.chainId));
  const reportDir = path.resolve(__dirname, "..", CONFIG.reportDir);
  fs.mkdirSync(reportDir, { recursive: true });
  const filename = path.join(reportDir, `maxTps-${report.timestamp}.json`);
  fs.writeFileSync(filename, JSON.stringify(report, null, 2));
  console.log(`Report saved: ${filename}`);
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
