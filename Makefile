-include .env

.PHONY: all test clean anvil anvil-persist anvil-base-sepolia anvil-base-sepolia-persist deploy-anvil deploy-anvil-create2 deploy-sepolia deploy-base-sepolia deploy-base-sepolia-create2 deploy-base deploy-base-create2 verify-base-create2

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install smartcontractkit/chainlink-brownie-contracts && forge install rari-capital/solmate && forge install foundry-rs/forge-std

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test

snapshot :; forge snapshot

slither :; slither ./contracts

format :; forge fmt

# solhint should be installed globally
lint :; solhint contracts/**/*.sol && solhint contracts/*.sol

anvil :; anvil -m 'test test test test test test test test test test test junk'

# Persist anvil state to disk under .anvil/dev.
.anvil/dev :; mkdir -p .anvil/dev
anvil-persist :.anvil/dev; anvil --state .anvil/dev --state-interval 10 -m 'test test test test test test test test test test test junk'

# Fork Base Sepolia locally on :8545 with chain id 84532 and the standard
# anvil test mnemonic. Requires BASE_SEPOLIA_RPC_URL in .env. See LOCAL_DEV.md.
anvil-base-sepolia :; anvil --fork-url ${BASE_SEPOLIA_RPC_URL} --chain-id 84532 -m 'test test test test test test test test test test test junk'

# Persist forked Base Sepolia local state under .anvil/base-sepolia.
.anvil/base-sepolia :; mkdir -p .anvil/base-sepolia
anvil-base-sepolia-persist :; anvil --state .anvil/base-sepolia --state-interval 10 --fork-url ${BASE_SEPOLIA_RPC_URL} --chain-id 84532 -m 'test test test test test test test test test test test junk'

# use the "@" to hide the command from your shell
deploy-sepolia :; @forge script script/DeployAll.s.sol:DeployAll --rpc-url ${SEPOLIA_RPC_URL} --broadcast --verify --etherscan-api-key ${ETHERSCAN_API_KEY} -vvvv

# Base Sepolia (chain id 84532). See DEPLOY_BASE_SEPOLIA.md for setup.
deploy-base-sepolia :; @forge script script/DeployAll.s.sol:DeployAll --rpc-url base_sepolia --broadcast --verify --verifier etherscan -vvvv

# Base mainnet (chain id 8453). Escrow only — arbitrator + capped tokens
# must already exist on-chain. See DEPLOY_BASE.md.
deploy-base :; @forge script script/DeployEscrow.s.sol:DeployEscrow --rpc-url base --broadcast --verify --verifier etherscan -vvvv

# This is the private key of account from the mnemonic from the "make anvil" command
deploy-anvil :; @forge script script/DeployAll.s.sol:DeployAll --rpc-url http://localhost:8545 --broadcast

# Deterministic deployment mode using CREATE2 (salt-driven).
deploy-anvil-create2 :; @NERWO_USE_CREATE2=true forge script script/DeployAll.s.sol:DeployAll --rpc-url http://localhost:8545 --broadcast
deploy-base-sepolia-create2 :; @NERWO_USE_CREATE2=true forge script script/DeployAll.s.sol:DeployAll --rpc-url base_sepolia --broadcast --verify --verifier etherscan -vvvv
deploy-base-create2 :; @NERWO_USE_CREATE2=true forge script script/DeployEscrow.s.sol:DeployEscrow --rpc-url base --broadcast --verify --verifier etherscan -vvvv
verify-base-create2 :; @forge script script/VerifyEscrowCreate2.s.sol:VerifyEscrowCreate2 --rpc-url base

-include ${FCT_PLUGIN_PATH}/makefile-external
