# Deploy to Base Sepolia

This guide deploys the Nerwo contracts (`NerwoCentralizedArbitrator`,
`NerwoEscrow`, and optionally `NerwoTetherToken`) to Base Sepolia using
the chain-agnostic [`script/DeployAll.s.sol`](script/DeployAll.s.sol)
forge script.

Base Sepolia chain id: **84532**.

## 1. Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`).
- A funded Base Sepolia deployer account.
  Faucets: <https://www.alchemy.com/faucets/base-sepolia>,
  <https://faucet.quicknode.com/base/sepolia>.
- A BaseScan API key for source verification:
  <https://basescan.org/myapikey>.
- (Optional) An RPC provider key (Alchemy / Infura / QuickNode). The
  public `https://sepolia.base.org` endpoint works but is heavily rate
  limited.

## 2. Configure environment

Copy the template and fill it in:

```sh
cp .env.base-sepolia.example .env
$EDITOR .env
```

Minimum required variables:

| Variable | Purpose |
| --- | --- |
| `PRIVATE_KEY` | Deployer key, hex-encoded with or without `0x`. |
| `BASE_SEPOLIA_RPC_URL` | Base Sepolia RPC endpoint. |
| `BASESCAN_API_KEY` | BaseScan key used by `--verify`. |

Optional overrides consumed by `DeployAll.s.sol`:

| Variable | Default | Notes |
| --- | --- | --- |
| `NERWO_OWNER_ADDRESS` | deployer | Owner of `NerwoEscrow` after construction. |
| `NERWO_COURT_ADDRESS` | owner | Owner of `NerwoCentralizedArbitrator`. |
| `NERWO_PLATFORM_ADDRESS` | owner | Fee recipient. |
| `NERWO_ARBITRATION_PRICE_WEI` | `0.02 ether` | Arbitration cost in wei. |
| `NERWO_FEE_RECIPIENT_BASISPOINT` | `550` | 550 = 5.5%. |
| `NERWO_ARBITRATOR_METAEVIDENCEURI` | empty | IPFS URI of the meta-evidence JSON. |
| `NERWO_ARBITRATOR_ADDRESS` | unset | Reuse an existing arbitrator instead of deploying. |
| `NERWO_ARBITRATORPROXY_ADDRESS` | unset | Reuse an existing arbitrator proxy. Both `*_ADDRESS` must be set together. |
| `NERWO_TOKENS_WHITELIST` | empty | Comma-separated ERC20 addresses. If empty, the script also deploys `NerwoTetherToken` and whitelists it. |
| `NERWO_USE_CREATE2` | `false` | Set to `true` for deterministic CREATE2 addresses. |
| `NERWO_ARBITRATOR_SALT` | `0x...01` | CREATE2 salt for arbitrator deployment (when deployed by script). |
| `NERWO_TEST_TOKEN_SALT` | `0x...02` | CREATE2 salt for test token deployment (when deployed by script). |
| `NERWO_ESCROW_SALT` | `0x...03` | CREATE2 salt for escrow deployment. |

The contract enforces that whitelisted tokens are plain ERC20s — see
the *Token whitelist* section of [README.md](README.md) before adding
any token to `NERWO_TOKENS_WHITELIST`.

## 3. Dry run

Simulate locally against the live chain state without broadcasting:

```sh
source .env
forge script script/DeployAll.s.sol:DeployAll --rpc-url base_sepolia
```

Review the predicted addresses, gas usage, and constructor arguments.

## 4. Deploy and verify

```sh
source .env
make deploy-base-sepolia
```

Deterministic CREATE2 mode:

```sh
source .env
make deploy-base-sepolia-create2
```

Equivalent raw command:

```sh
forge script script/DeployAll.s.sol:DeployAll \
    --rpc-url base_sepolia \
    --broadcast \
    --verify \
    --verifier etherscan \
    -vvvv
```

Foundry reads the chain RPC and the BaseScan API key from the
`[rpc_endpoints]` and `[etherscan]` sections of
[`foundry.toml`](foundry.toml), so no extra CLI flags are needed.

Broadcast artifacts (transactions, receipts, deployed addresses) are
written to `broadcast/DeployAll.s.sol/84532/`.

## 5. Post-deploy checklist

- Note the addresses printed at the end of the run (arbitrator, escrow,
  optional test token).
- Confirm the contracts are verified on
  <https://sepolia.basescan.org>.
- If `NERWO_ARBITRATOR_METAEVIDENCEURI` was left blank, call
  `NerwoEscrow.setMetaEvidenceURI(uri)` from the owner once the
  meta-evidence JSON is pinned.
- If a non-deployer owner was used, double-check that ownership
  actually transferred (`owner()` on both contracts).

## 6. Troubleshooting

- **Verification fails right after deploy.** BaseScan often lags by
  ~30s. Re-run verification standalone:

  ```sh
  forge verify-contract <address> contracts/NerwoEscrow.sol:NerwoEscrow \
      --chain base-sepolia \
      --watch
  ```

- **`insufficient funds for gas`.** Top up the deployer from a Base
  Sepolia faucet (see prerequisites).

- **`unknown chain`.** Update Foundry: `foundryup`. Base Sepolia
  shipped as a built-in chain in recent releases.

- **Public RPC rate-limits the script.** Switch
  `BASE_SEPOLIA_RPC_URL` to a private provider URL.
