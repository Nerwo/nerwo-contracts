import { DeployFunction } from 'hardhat-deploy/types';
import * as constants from '../constants';

const func: DeployFunction = async function ({ deployments: { get, deploy }, getNamedAccounts }) {
  const { deployer, platform } = await getNamedAccounts();
  const arbitrator = await get('NerwoCentralizedArbitratorV1');

  await deploy('NerwoEscrowV1', {
    from: deployer,
    proxy: {
      proxyContract: 'UUPS',
      execute: {
        init: {
          methodName: 'initialize',
          args: [
            arbitrator.address,
            [],
            platform,
            constants.FEE_RECIPIENT_BASISPOINT,
            constants.FEE_TIMEOUT
          ]
        }
      }
    },
    log: true
  });
};

export default func;
func.tags = ['NerwoEscrowV1'];
