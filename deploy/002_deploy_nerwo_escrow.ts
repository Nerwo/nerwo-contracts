import { DeployFunction } from 'hardhat-deploy/types';
import * as constants from '../constants';
import { escrowArgs } from '../constructors';

const func: DeployFunction = async function ({ deployments: { get, deploy }, getNamedAccounts }) {
  let { deployer, platform } = await getNamedAccounts();
  platform = platform || deployer;

  const arbitrator = await get('NerwoCentralizedArbitrator');

  let usdt;
  try {
    usdt = await get('NerwoTetherToken');
  } catch (_) { }

  const args = escrowArgs(deployer, arbitrator.address, platform, usdt?.address);

  await deploy('NerwoEscrow', {
    from: deployer,
    args: args,
    log: true,
    deterministicDeployment: true
  });
};

export default func;
func.tags = ['NerwoEscrow'];
func.dependencies = ['NerwoCentralizedArbitrator'];
