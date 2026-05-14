# Local development

How to run a local chain, deploy the full Nerwo stack on it, connect a
frontend, and poke contracts from a GUI.

Two flavors:

| Mode | Command | Use when |
| --- | --- | --- |
| Plain anvil | `make anvil` | You only need a fresh dev chain. Chain id `31337`. |
| Forked Base Sepolia | `make anvil-base-sepolia` | You want the existing Base Sepolia state available locally (real tokens, real arbitrator, etc). Chain id `84532`. |
| Plain anvil (persistent) | `make anvil-persist` | You want local state to survive stop/start. Chain id `31337`. |
| Forked Base Sepolia (persistent) | `make anvil-base-sepolia-persist` | You want fork + local writes to survive stop/start. Chain id `84532`. |

Both use the standard test mnemonic, so the 10 dev accounts below are
prefunded with 10 000 ETH each.

## 1. Start the chain

```sh
# fresh chain
make anvil

# OR — fork Base Sepolia (needs BASE_SEPOLIA_RPC_URL in .env)
make anvil-base-sepolia
```

Leave the process running. It listens on `http://127.0.0.1:8545`.

## 2. Deploy the full stack

In another shell:

```sh
make deploy-anvil
```

This runs [`script/DeployAll.s.sol`](script/DeployAll.s.sol) and
deploys, in order: `NerwoCentralizedArbitrator`, `NerwoTetherToken`
(used as the whitelisted ERC20 for tests), and `NerwoEscrow`. The
deployer is anvil account `#0`; ownership stays on `#0` unless you
override `NERWO_OWNER_ADDRESS`.

If you need deterministic addresses across chains and environments,
use CREATE2 mode:

```sh
make deploy-anvil-create2
```

Salt env vars (optional):

- `NERWO_ARBITRATOR_SALT` (defaults to `0x...01`)
- `NERWO_TEST_TOKEN_SALT` (defaults to `0x...02`)
- `NERWO_ESCROW_SALT` (defaults to `0x...03`)

CREATE2 gives the same address when deployer address, constructor args,
salt, and bytecode are the same. If any one of these changes, the
resulting address changes too.

Deployed addresses are printed at the end of the run and also saved
under `broadcast/DeployAll.s.sol/<chainId>/run-latest.json`. Quick way
to extract them:

```sh
jq '.transactions[] | {contract: .contractName, address: .contractAddress}' \
  broadcast/DeployAll.s.sol/31337/run-latest.json
```

(Replace `31337` with `84532` if you used the Base Sepolia fork.)

## 3. Connect MetaMask

Add a custom network:

| Field | Plain anvil | Forked Base Sepolia |
| --- | --- | --- |
| Network name | `Anvil local` | `Base Sepolia (local fork)` |
| RPC URL | `http://127.0.0.1:8545` | `http://127.0.0.1:8545` |
| Chain ID | `31337` | `84532` |
| Currency symbol | `ETH` | `ETH` |
| Block explorer | *(leave blank)* | *(leave blank)* |

Then import one of the test accounts below ("Add account" → "Import
account" → paste the private key).

## 4. Interact via GUI

### Option A — Remix IDE (fast, zero install)

1. Open <https://remix.ethereum.org>.
2. *Deploy & run transactions* tab → **Environment** → **Custom -
   External Http Provider** → URL `http://127.0.0.1:8545`.
3. *At Address* field: paste the deployed `NerwoEscrow` (or
   arbitrator) address.
4. Pick the matching contract from the dropdown (compile it once in
   Remix or upload the artifact from `out/`).
5. All read/write methods show up as buttons. Anvil signs with the
   selected account.

### Option B — Otterscan (Etherscan-like local explorer)

```sh
docker run --rm -p 5100:80 --name otterscan \
  -e ERIGON_URL=http://host.docker.internal:8545 \
  otterscan/otterscan:latest
```

Open <http://localhost:5100>. Useful for inspecting tx traces, decoded
calldata, and state changes. Less useful for "press a button to call a
method" — use Remix for that.

### Option C — frontend

Point the frontend's RPC at `http://127.0.0.1:8545` and the chain id at
the value from the table in step 3. The deployed addresses come from
the broadcast JSON in step 2.

## 5. Reset

If you started with `make anvil` / `make anvil-base-sepolia`, stop
anvil (`Ctrl-C`) and start it again to reset in-memory state, then
re-run `make deploy-anvil`.

If you started with `make anvil-persist` /
`make anvil-base-sepolia-persist`, stop/start reloads from
`.anvil/dev/state.json` or `.anvil/base-sepolia/state.json`.
Delete those files/directories when you want a clean reset.

## Test accounts (anvil default mnemonic)

> Mnemonic: `test test test test test test test test test test test junk`
>
> These keys are **public and well-known**. Never use them on a
> non-local network or with real funds.

| # | Address | Private key |
| --- | --- | --- |
| 0 | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| 1 | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` |
| 2 | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` |
| 3 | `0x90F79bf6EB2c4f870365E785982E1f101E93b906` | `0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6` |
| 4 | `0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65` | `0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a` |
| 5 | `0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc` | `0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba` |
| 6 | `0x976EA74026E726554dB657fA54763abd0C3a0aa9` | `0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e` |
| 7 | `0x14dC79964da2C08b23698B3D3cc7Ca32193d9955` | `0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356` |
| 8 | `0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f` | `0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97` |
| 9 | `0xa0Ee7A142d267C1f36714E4a8F75612F20a79720` | `0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dfa6dd0e8e` |

Account `#0` is the deployer / owner / court / fee recipient in
`DeployAll` defaults. Use accounts `#1` and `#2` as client and
freelancer when exercising the escrow flow.
