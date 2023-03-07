import { DeployFunction } from 'hardhat-deploy/types';

import * as constants from '../constants';

const func: DeployFunction = async function ({ deployments: { deploy }, getNamedAccounts }) {
  let { deployer, court } = await getNamedAccounts();
  court = court || process.env.NERWO_COURT_ADDRESS;

  await deploy('NerwoCentralizedArbitrator', {
    from: deployer,
    args: [court, constants.ARBITRATOR_PRICE],
    log: true,
    deterministicDeployment: true
  });
};

export default func;
func.tags = ['NerwoCentralizedArbitrator'];
