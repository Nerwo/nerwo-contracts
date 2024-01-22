import { DeployFunction } from 'hardhat-deploy/types';
import { escrowArgs } from '../constructors';

const func: DeployFunction = async function ({ deployments: { get, deploy }, getNamedAccounts }) {
  let { deployer, platform } = await getNamedAccounts();
  platform = platform || deployer;

  let arbitrator;
  try {
    arbitrator = await get('NerwoCentralizedArbitrator');
  } catch (_) { }

  let usdt;
  try {
    usdt = await get('NerwoTetherToken');
  } catch (_) { }

  const args = escrowArgs(platform, arbitrator?.address, platform, usdt?.address);
  await deploy('NerwoEscrow', {
    args: args,
    from: deployer,
    log: true
  });
};

export default func;
func.tags = ['NerwoEscrow'];
func.dependencies = ['NerwoCentralizedArbitrator'];
