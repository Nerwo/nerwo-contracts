# Gas and Deployment Costs

This project uses Foundry/Forge for gas and deployment estimates.

## Contract Size

Check deployed bytecode and initcode size:

```bash
forge build --sizes
```

## Compiler Gas Estimates

Ask `solc` for static gas estimates:

```bash
forge inspect NerwoEscrow gasEstimates
```

These estimates are useful for a quick comparison, but they are not a full
transaction simulation.

## Function Gas Reports

Measure gas for tested runtime paths:

```bash
forge test --gas-report
```

For a focused report, filter to the relevant test first:

```bash
forge test --match-test <TEST_NAME> --gas-report
```

This is more useful than `solc` gas estimates for functions that include
external calls, dynamic data, or storage writes whose cost depends on current
state. In those cases `forge inspect ... gasEstimates` may report `infinite`,
which means the compiler could not prove a static upper bound.

## Deployment Gas

Simulate a deploy script without broadcasting:

```bash
forge script script/DeployEscrow.s.sol --rpc-url <RPC_URL>
```

Broadcast only when ready:

```bash
forge script script/DeployEscrow.s.sol --rpc-url <RPC_URL> --broadcast
```

When using Anvil or Hardhat locally, the reported gas price is a local chain
value. Use the reported gas units for estimates, but multiply them by the real
network gas price before deciding whether to deploy.

Example local output:

```text
Paid: 0.000475720255411035 ETH (539745 gas * 0.881379643 gwei)
```

For a real-chain estimate, keep `539745 gas` and replace `0.881379643 gwei`
with the current network gas price.

## Gwei to ETH

The unit conversions are:

```text
1 ETH  = 1,000,000,000,000,000,000 wei
1 gwei = 1,000,000,000 wei
1 gwei = 0.000000001 ETH
```

Deployment cost in ETH:

```text
cost_eth = gas_used * gas_price_gwei / 1,000,000,000
```

Examples for a deployment that uses `539745` gas:

```text
539745 gas * 1 gwei  / 1,000,000,000 = 0.000539745 ETH
539745 gas * 5 gwei  / 1,000,000,000 = 0.002698725 ETH
539745 gas * 10 gwei / 1,000,000,000 = 0.00539745 ETH
```

On L2 networks, the final charged amount can include additional L1 data fees.
The `gas_used * gas_price` calculation is still useful, but it may not be the
complete transaction cost.
