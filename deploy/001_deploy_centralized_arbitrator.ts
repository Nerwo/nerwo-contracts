import { DeployFunction } from 'hardhat-deploy/types';
import { parseEther } from 'ethers/lib/utils';

const func: DeployFunction = async function ({ deployments: { deploy, execute }, getChainId, getNamedAccounts }) {
  const ARBITRATOR_PRICE = parseEther(process.env.NERWO_ARBITRATION_PRICE);
  const { deployer } = await getNamedAccounts();

  await deploy('CentralizedArbitrator', {
    from: deployer,
    args: [ARBITRATOR_PRICE],
    log: true
  });

  await execute('CentralizedArbitrator', {
    from: deployer,
    log: true
  },
    'transferOwnership',
    process.env.NERWO_COURT_ADDRESS);
};

export default func;
func.tags = ['CentralizedArbitrator'];
