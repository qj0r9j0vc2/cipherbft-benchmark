## Quickstart

```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup

source ~/.bashrc

foundryup

git clone https://github.com/qj0r9j0vc2/cipherbft-benchmark
cd cipherbft-benchmark/
forge install

vi foundry.toml
---
[profile.default]
fs_permissions = [{ access = "read-write", path = "benchmark-results" }]
---

forge script script/Deploy.s.sol:DeployToken --rpc-url http://localhost:8545 --private-key <private-key> --broadcast

export TOKEN_ADDRESS=<token-address>

mkdir -p benchmark-results/
forge script script/benchmark/LoadTest.s.sol --rpc-url http://localhost:8545 --private-key <private-key> --broadcast 

```
