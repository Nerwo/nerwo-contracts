import { DeployFunction } from 'hardhat-deploy/types';

import { arbitratorArgs } from '../constructors';

const func: DeployFunction = async function ({ deployments: { deploy, execute }, getNamedAccounts }) {
  const { deployer, court } = await getNamedAccounts();

  const result = await deploy('NerwoCentralizedArbitrator', {
    from: deployer,
    log: true,
    deterministicDeployment: true
  });

  if (!result.newlyDeployed) {
    return;
  }

  const args = arbitratorArgs(court);
  await execute('NerwoCentralizedArbitrator', {
    from: deployer,
    log: true
  }, 'initialize', ...args);
};

export default func;
func.tags = ['NerwoCentralizedArbitrator'];
