import { DeployFunction } from 'hardhat-deploy/types';

import { arbitratorArgs } from '../constructors';

const func: DeployFunction = async function ({ deployments: { deploy }, getNamedAccounts }) {
  const { deployer, court } = await getNamedAccounts();

  const args = arbitratorArgs(court);
  await deploy('NerwoCentralizedArbitrator', {
    args: args,
    from: deployer,
    log: true
  });
};

export default func;
func.tags = ['NerwoCentralizedArbitrator'];
