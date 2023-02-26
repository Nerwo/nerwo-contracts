import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function ({ deployments: { get, deploy }, getNamedAccounts }) {
  const { deployer } = await getNamedAccounts();
  const arbitrator = await get('CentralizedArbitrator');

  await deploy('MultipleArbitrableTransactionWithFee', {
    from: deployer,
    args: [
      arbitrator.address,
      [], // _arbitratorExtraData
      process.env.NERWO_PLATFORM_ADDRESS,
      process.env.NERWO_FEE_RECIPIENT_BASISPOINT,
      process.env.NERWO_FEE_TIMEOUT
    ],
    log: true
  });
};

export default func;
func.tags = ['MultipleArbitrableTransactionWithFee'];
func.dependencies = ['CentralizedArbitrator'];
