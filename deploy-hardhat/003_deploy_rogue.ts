import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function ({ deployments: { get, deploy }, getNamedAccounts }) {
  let { deployer } = await getNamedAccounts();
  const escrow = await get('NerwoEscrow');

  await deploy('Rogue', {
    from: deployer,
    args: [escrow.address],
    log: true,
  });
};

export default func;
func.tags = ['Rogue'];
func.dependencies = ['NerwoEscrow'];
