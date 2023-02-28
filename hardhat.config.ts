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
    compilers: [
      { version: '0.4.24' },
      { version: '0.8.19' }
    ]
  },
  namedAccounts: {
    deployer: 0,
  },
  gasReporter: {
    enabled: (process.env.REPORT_GAS) ? true : false,
    excludeContracts: [
      'AutoAppealableArbitrator',
      'MultipleArbitrableTransaction', 'MultipleArbitrableTransactionWithFee']
  },
  networks: {
    goerli: {
      url: process.env.RPC_URL,
      accounts: [process.env.PRIVATE_KEY]
    },
    hardhat: {
      accounts: {
        mnemonic: process.env.HARDHAT_MNEMONIC || HARDHAT_NETWORK_MNEMONIC
      },
      deploy: ['deploy-hardhat']
    }
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  }
};

export default config;
