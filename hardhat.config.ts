import { parseArgs } from 'node:util';
import { HardhatUserConfig } from 'hardhat/config';
import { HARDHAT_NETWORK_MNEMONIC } from 'hardhat/internal/core/config/default-config';
import '@nomicfoundation/hardhat-toolbox';
import '@nomiclabs/hardhat-etherscan';
import '@nomiclabs/hardhat-ethers';
import 'hardhat-gas-reporter';
import 'hardhat-deploy';

import * as dotenv from 'dotenv';
dotenv.config();

const options = { network: { type: 'string' as 'string' } };
const network = parseArgs({ options: options, strict: false }).values.network;

if (network) {
  dotenv.config({ path: `.env.${network}`, override: true });
}

const BUILDBEAR_CONTAINER_NAME = process.env.BUILDBEAR_CONTAINER_NAME || 'invalid';

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.18',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
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
    excludeContracts: ['Rogue', 'TetherToken', 'ERC20']
  },
  networks: {
    sepolia: {
      url: process.env.RPC_URL,
      accounts: [process.env.PRIVATE_KEY],
      verify: {
        etherscan: {
          apiKey: process.env.ETHERSCAN_API_KEY
        }
      },
      deploy: ['deploy', 'deploy-testing']
    },
    hardhat: {
      accounts: {
        mnemonic: process.env.HARDHAT_MNEMONIC || HARDHAT_NETWORK_MNEMONIC
      },
      deploy: ['deploy', 'deploy-testing']
    },
    buildbear: {
      url: `https://rpc.buildbear.io/${BUILDBEAR_CONTAINER_NAME}`,
      accounts: {
        mnemonic: process.env.BUILDBEAR_MNEMONIC || HARDHAT_NETWORK_MNEMONIC
      },
      verify: {
        etherscan: {
          apiKey: 'verifyContract',
          // FIXME: 404 /api?
          apiUrl: `https://rpc.buildbear.io/verify/etherscan/${BUILDBEAR_CONTAINER_NAME}`
        }
      }
    }
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY || '',
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
