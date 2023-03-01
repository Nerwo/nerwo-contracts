import { DeployFunction } from 'hardhat-deploy/types';
import { deployments, ethers, upgrades } from 'hardhat';

import * as constants from '../constants';

const func: DeployFunction = async function ({ deployments: { execute, save }, getNamedAccounts }) {
  const { deployer } = await getNamedAccounts();

  const NerwoCentralizedArbitratorV1 = await ethers.getContractFactory("NerwoCentralizedArbitratorV1");
  const proxy = await upgrades.deployProxy(NerwoCentralizedArbitratorV1, [constants.ARBITRATOR_PRICE], {
    kind: 'uups',
    initializer: 'initialize',
  });
  await proxy.deployed();

  const artifact = await deployments.getExtendedArtifact('NerwoCentralizedArbitratorV1');
  const proxyDeployments = { address: proxy.address, ...artifact };
  await save('NerwoCentralizedArbitratorV1', proxyDeployments);

  console.log(`NerwoCentralizedArbitratorV1 deployed at ${proxy.address}`);

  await execute('NerwoCentralizedArbitratorV1', {
    from: deployer,
    log: true
  },
    'transferOwnership',
    process.env.NERWO_COURT_ADDRESS);
};

export default func;
func.tags = ['NerwoCentralizedArbitratorV1'];
