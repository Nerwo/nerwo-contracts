import { DeployFunction } from 'hardhat-deploy/types';

import * as constants from '../constants';

const func: DeployFunction = async function ({ deployments: { deploy }, getNamedAccounts }) {
  let { deployer, court } = await getNamedAccounts();
  court = court || process.env.NERWO_COURT_ADDRESS;

  await deploy('NerwoCentralizedArbitratorV1', {
    from: deployer,
    proxy: {
      proxyContract: 'UUPS',
      execute: {
        init: {
          methodName: 'initialize',
          args: [court, constants.ARBITRATOR_PRICE]
        }
      }
    },
    log: true,
    deterministicDeployment: true
  });
};

export default func;
func.tags = ['NerwoCentralizedArbitratorV1'];
