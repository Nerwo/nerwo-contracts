# Echidna setup

Run the NerwoEscrow property harness with:

```sh
echidna test/echidna/NerwoEscrowEchidna.sol --contract NerwoEscrowEchidna --config echidna.config.yml
```

The harness deploys `NerwoEscrow` with its constructor dependencies and checks:

- escrow token balance covers tracked open ERC20 escrows
- escrow native balance covers tracked open native escrows plus credited withdrawals
- `lastTransaction` remains monotonic against successful harness-created transactions
