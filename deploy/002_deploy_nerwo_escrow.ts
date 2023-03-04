import { DeployFunction } from 'hardhat-deploy/types';
import * as constants from '../constants';

const func: DeployFunction = async function ({ deployments: { get, deploy }, getNamedAccounts }) {
  let { deployer, platform } = await getNamedAccounts();
  const arbitrator = await get('NerwoCentralizedArbitratorV1');

  platform = platform || deployer;

  await deploy('NerwoEscrowV1', {
    from: deployer,
    proxy: {
      proxyContract: 'UUPS',
      execute: {
        init: {
          methodName: 'initialize',
          args: [
            arbitrator.address,                 /* _arbitrator */
            [],                                 /* _arbitratorExtraData */
            constants.FEE_TIMEOUT,              /* _feeTimeout */
            constants.MINIMAL_AMOUNT,           /* _minimalAmount */
            platform,                           /* _feeRecipient */
            constants.FEE_PRICE_THRESHOLDS      /* _priceThresholds */
          ]
        }
      }
    },
    log: true
  });
};

export default func;
func.tags = ['NerwoEscrowV1'];
