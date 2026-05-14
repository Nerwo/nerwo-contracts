-include .env

.PHONY: all test clean deploy-anvil deploy-sepolia deploy-base-sepolia deploy-base

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

# use the "@" to hide the command from your shell
deploy-sepolia :; @forge script script/DeployAll.s.sol:DeployAll --rpc-url ${SEPOLIA_RPC_URL} --broadcast --verify --etherscan-api-key ${ETHERSCAN_API_KEY} -vvvv

# Base Sepolia (chain id 84532). See DEPLOY_BASE_SEPOLIA.md for setup.
deploy-base-sepolia :; @forge script script/DeployAll.s.sol:DeployAll --rpc-url base_sepolia --broadcast --verify --verifier etherscan -vvvv

# Base mainnet (chain id 8453). Escrow only — arbitrator + token whitelist
# must already exist on-chain. See DEPLOY_BASE.md.
deploy-base :; @forge script script/DeployEscrow.s.sol:DeployEscrow --rpc-url base --broadcast --verify --verifier etherscan -vvvv

# This is the private key of account from the mnemonic from the "make anvil" command
deploy-anvil :; @forge script script/DeployAll.s.sol:DeployAll --rpc-url http://localhost:8545 --broadcast

-include ${FCT_PLUGIN_PATH}/makefile-external
