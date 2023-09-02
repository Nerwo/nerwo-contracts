import { DeployFunction } from 'hardhat-deploy/types';
import { escrowArgs } from '../constructors';

const func: DeployFunction = async function ({ deployments: { get, deploy, execute }, getNamedAccounts }) {
  let { deployer, platform } = await getNamedAccounts();
  platform = platform || deployer;

  let arbitrator;
  try {
    arbitrator = await get('NerwoCentralizedArbitrator');
  } catch (_) { }

  const result = await deploy('NerwoEscrow', {
    from: deployer,
    log: true,
    deterministicDeployment: true
  });

  if (!result.newlyDeployed) {
    return;
  }

  let usdt;
  try {
    usdt = await get('NerwoTetherToken');
  } catch (_) { }

  const args = escrowArgs(platform, arbitrator?.address, platform, usdt?.address);
  await execute('NerwoEscrow', {
    from: deployer,
    log: true
  }, 'initialize', ...args);
};

export default func;
func.tags = ['NerwoEscrow'];
func.dependencies = ['NerwoCentralizedArbitrator'];
