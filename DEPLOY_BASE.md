# Deploy NerwoEscrow to Base mainnet

Production deploy of **`NerwoEscrow` only**. The arbitrator, arbitrable
proxy, and any ERC20 tokens you intend to enable must already exist
on Base mainnet — this profile refuses to deploy a centralized
arbitrator or a test ERC20.

If you also need to deploy the arbitrator (e.g. for a testnet rehearsal),
use `make deploy-base-sepolia` (see [DEPLOY_BASE_SEPOLIA.md](DEPLOY_BASE_SEPOLIA.md))
or run [`script/DeployAll.s.sol`](script/DeployAll.s.sol) manually.

Base mainnet chain id: **8453**.

## 1. Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
  (`forge`, `cast`).
- Deployer account funded with Base ETH for gas.
- BaseScan API key for source verification:
  <https://basescan.org/myapikey>.
- Private RPC endpoint (Alchemy / Infura / QuickNode) strongly
  recommended over the public `https://mainnet.base.org`.
- **Pre-existing on-chain**:
  - Arbitrator address (e.g. an `NerwoCentralizedArbitrator` already
    deployed and owned by the court multisig).
  - Arbitrable proxy address.
  - At least one ERC20 token address compatible with the token-cap
    policy in [README.md](README.md).

## 2. Configure environment

```sh
cp .env.base.example .env
$EDITOR .env
```

Required variables:

| Variable | Purpose |
| --- | --- |
| `PRIVATE_KEY` | Deployer key. |
| `BASE_RPC_URL` | Base mainnet RPC. |
| `BASESCAN_API_KEY` | Verification key. |
| `NERWO_ARBITRATOR_ADDRESS` | Existing arbitrator. |
| `NERWO_ARBITRATORPROXY_ADDRESS` | Existing arbitrable proxy. |
| `NERWO_TOKENS_WHITELIST` | Comma-separated existing ERC20s to cap-enable. |
| `NERWO_TOKEN_CAPS` | Comma-separated raw-unit per-transaction caps, one per token. Use `uint256.max` for unlimited. |

Optional overrides:

| Variable | Default | Notes |
| --- | --- | --- |
| `NERWO_OWNER_ADDRESS` | deployer | Owner of the escrow after construction. Use a multisig in production. |
| `NERWO_PLATFORM_ADDRESS` | owner | Fee recipient. |
| `NERWO_FEE_RECIPIENT_BASISPOINT` | `550` | 550 = 5.5%. |
| `NERWO_ARBITRATOR_METAEVIDENCEURI` | empty | IPFS URI, can also be set post-deploy via `setMetaEvidenceURI`. |
| `NERWO_USE_CREATE2` | `false` | Set to `true` for deterministic CREATE2 address. |
| `NERWO_ESCROW_SALT` | `0x...03` | CREATE2 salt for escrow deployment. |

The script reverts with a custom error if any of `NERWO_ARBITRATOR_ADDRESS`,
`NERWO_ARBITRATORPROXY_ADDRESS`, a non-empty `NERWO_TOKENS_WHITELIST`,
or matching `NERWO_TOKEN_CAPS` are missing.

## 3. Dry run

Simulate against live state without broadcasting. **Do this first.**

```sh
source .env
forge script script/DeployEscrow.s.sol:DeployEscrow --rpc-url base
```

Confirm:

- Constructor args (owner, arbitrator pair, fee recipient, basis point,
  meta-evidence URI) match expectations.
- Follow-up `changeTokenCap` calls set the expected token caps.
- Predicted gas cost is reasonable.
- The deployer has enough Base ETH to cover it.

## 4. Deploy

```sh
source .env
make deploy-base
```

Deterministic CREATE2 mode:

```sh
source .env
make deploy-base-create2
```

Optional preflight check for CREATE2 deployments (verifies predicted
address, deployed bytecode, and key on-chain config):

```sh
source .env
make verify-base-create2
```

Equivalent raw command:

```sh
forge script script/DeployEscrow.s.sol:DeployEscrow \
    --rpc-url base \
    --broadcast \
    --verify \
    --verifier etherscan \
    -vvvv
```

`--rpc-url base` and `--verify` resolve via `[rpc_endpoints]` and
`[etherscan]` in [`foundry.toml`](foundry.toml).

Broadcast artifacts land in `broadcast/DeployEscrow.s.sol/8453/`.

## 5. Post-deploy checklist

- Record the escrow address printed at the end of the run.
- Confirm verification on <https://basescan.org>.
- `owner()` returns the expected owner (the deployer was only used to
  sign the transaction; the constructor transfers ownership to
  `NERWO_OWNER_ADDRESS`).
- `getArbitrationCost()` returns the expected value via the linked
  arbitrator.
- Token caps look correct (`TokenCapChanged` events in the deploy
  receipt).
- If `NERWO_ARBITRATOR_METAEVIDENCEURI` was left blank, the owner
  should call `setMetaEvidenceURI(uri)` once the meta-evidence JSON is
  pinned.

## 6. Troubleshooting

- **`MissingArbitrator` / `MissingArbitratorProxy` / `MissingTokenCapTokens` / `MissingTokenCaps`.**
  The script asserts these are set and non-zero — fill them in `.env`.
- **`TokenCapsLengthMismatch`.** `NERWO_TOKENS_WHITELIST` and
  `NERWO_TOKEN_CAPS` must have the same number of comma-separated
  entries.
- **Verification fails immediately.** BaseScan can lag by ~30s. Re-run
  verification standalone:

  ```sh
  forge verify-contract <address> contracts/NerwoEscrow.sol:NerwoEscrow \
      --chain base \
      --watch
  ```

- **`insufficient funds for gas`.** Top up the deployer with Base ETH.
- **Public RPC errors.** Switch `BASE_RPC_URL` to a private provider.
