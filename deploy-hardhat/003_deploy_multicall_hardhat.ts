import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function ({ deployments: { get, deploy }, getChainId, getNamedAccounts }) {
  const { deployer } = await getNamedAccounts();

  await deploy('Multicall', {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: true
  });

  await deploy('Multicall2', {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: true
  });
};

export default func;
func.tags = ['Multicall', 'Multicall2'];
func.dependencies = ['CentralizedArbitrator'];
