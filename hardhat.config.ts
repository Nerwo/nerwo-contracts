import { HardhatUserConfig } from 'hardhat/config';
import { HARDHAT_NETWORK_MNEMONIC } from 'hardhat/internal/core/config/default-config';
import '@nomicfoundation/hardhat-toolbox';
import '@nomiclabs/hardhat-etherscan';
import '@openzeppelin/hardhat-upgrades';
import 'hardhat-gas-reporter';
import 'hardhat-abi-exporter';
import 'hardhat-deploy';

import * as dotenv from 'dotenv';
dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.19'
  },
  namedAccounts: {
    deployer: 0,
    platform: 1
  },
  gasReporter: {
    enabled: (process.env.REPORT_GAS) ? true : false,
    excludeContracts: ['Rogue']
  },
  networks: {
    goerli: {
      url: process.env.RPC_URL,
      accounts: [process.env.PRIVATE_KEY],
      verify: {
        etherscan: {
          apiKey: process.env.ETHERSCAN_API_KEY
        }
      }
    },
    hardhat: {
      accounts: {
        mnemonic: process.env.HARDHAT_MNEMONIC || HARDHAT_NETWORK_MNEMONIC
      }
    }
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  }
};

export default config;
