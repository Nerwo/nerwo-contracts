import { DeployFunction } from 'hardhat-deploy/types';

import * as constants from '../constants';

const func: DeployFunction = async function ({ deployments: { deploy, execute }, getNamedAccounts }) {
  const { deployer } = await getNamedAccounts();

  await deploy('NerwoCentralizedArbitratorV1', {
    from: deployer,
    proxy: {
      proxyContract: 'UUPS',
      execute: {
        init: {
          methodName: 'initialize',
          args: [constants.ARBITRATOR_PRICE]
        }
      }
    },
    log: true
  });

  if (deployer != process.env.NERWO_COURT_ADDRESS) {
    await execute('NerwoCentralizedArbitratorV1', {
      from: deployer,
      log: true
    },
      'transferOwnership',
      process.env.NERWO_COURT_ADDRESS);
  }
};

export default func;
func.tags = ['NerwoCentralizedArbitratorV1'];
