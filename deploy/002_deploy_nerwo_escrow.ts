import { DeployFunction } from 'hardhat-deploy/types';
import { deployments, ethers, upgrades } from 'hardhat';
import * as constants from '../constants';

const func: DeployFunction = async function ({ deployments: { get, save }, getNamedAccounts }) {
  const { platform } = await getNamedAccounts();

  const NerwoEscrowV1 = await ethers.getContractFactory("NerwoEscrowV1");

  const arbitrator = await get('NerwoCentralizedArbitratorV1');
  const proxy = await upgrades.deployProxy(NerwoEscrowV1, [
    arbitrator.address,
    [],
    platform,
    constants.FEE_RECIPIENT_BASISPOINT,
    constants.FEE_TIMEOUT
  ], {
    kind: 'uups',
    initializer: 'initialize',
  });
  await proxy.deployed();

  const artifact = await deployments.getExtendedArtifact('NerwoEscrowV1');
  const proxyDeployments = { address: proxy.address, ...artifact };
  await save('NerwoEscrowV1', proxyDeployments);

  console.log(`NerwoEscrowV1 deployed at ${proxy.address}`);
};

export default func;
func.tags = ['NerwoEscrowV1'];
