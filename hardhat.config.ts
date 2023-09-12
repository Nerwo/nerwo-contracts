import { parseArgs } from 'node:util';
import { HardhatUserConfig } from 'hardhat/config';
import { HARDHAT_NETWORK_MNEMONIC } from 'hardhat/internal/core/config/default-config';
import '@nomicfoundation/hardhat-toolbox';
import '@nomicfoundation/hardhat-ethers';
import '@truffle/dashboard-hardhat-plugin';
import 'hardhat-gas-reporter';
import 'hardhat-deploy';

import * as dotenv from 'dotenv';
dotenv.config();

const options = { network: { type: 'string' as 'string' } };
global.network = String(parseArgs({ options: options, strict: false }).values.network || 'localhost');

if (network) {
  dotenv.config({ path: `.env.${global.network}`, override: true });
}

const BUILDBEAR_CONTAINER_NAME = process.env.BUILDBEAR_CONTAINER_NAME || 'invalid';

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.21',
    settings: {
      evmVersion: 'shanghai', // paris for chains not supporting push0
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  namedAccounts: {
    deployer: 0,
    platform: 1,
    court: 2
  },
  gasReporter: {
    enabled: (process.env.REPORT_GAS) ? true : false,
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    excludeContracts: ['NerwoTetherToken']
  },
  /* - for token only deploy
  paths: {
    deploy: 'deploy-token'
  },
  */
  networks: {
    sepolia: {
      url: `https://eth-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_SEPOLIA_KEY || ''}`,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : undefined,
      deploy: ['deploy-token', 'deploy']
    },
    hardhat: {
      accounts: {
        mnemonic: process.env.HARDHAT_MNEMONIC || HARDHAT_NETWORK_MNEMONIC
      },
      deploy: ['deploy-test', 'deploy-token', 'deploy']
    },
    buildbear: {
      url: `https://rpc.buildbear.io/${BUILDBEAR_CONTAINER_NAME}`,
      accounts: {
        mnemonic: process.env.BUILDBEAR_MNEMONIC || HARDHAT_NETWORK_MNEMONIC
      }
    }
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY || '',
      sepolia: process.env.ETHERSCAN_API_KEY || '',
      buildbear: 'verifyContract'
    },
    customChains: [
      {
        network: 'buildbear',
        chainId: parseInt(process.env.BUILDBEAR_CHAINID || '1', 10),
        urls: {
          apiURL: `https://rpc.buildbear.io/verify/etherscan/${BUILDBEAR_CONTAINER_NAME}`,
          browserURL: `https://explorer.buildbear.io/${BUILDBEAR_CONTAINER_NAME}`,
        },
      },
    ],
  }
};

export default config;
