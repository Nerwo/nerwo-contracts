import { DeployFunction } from 'hardhat-deploy/types';
import * as constants from '../constants';

const func: DeployFunction = async function ({ deployments: { get, deploy }, getNamedAccounts }) {
  let { deployer, platform } = await getNamedAccounts();
  platform = platform || deployer;

  const arbitrator = await get('NerwoCentralizedArbitrator');

  let whitelist = constants.TOKENS_WHITELIST;

  // whitelist our test token if deployed
  // fake first address, for gas calculation
  try {
    const nerwoUSDT = await get('NerwoTetherToken');
    whitelist = process.env.REPORT_GAS ? [arbitrator.address, nerwoUSDT.address] : [nerwoUSDT.address];
  } catch (_) { }

  await deploy('NerwoEscrow', {
    from: deployer,
    args: [
      deployer,                           /* _owner */
      arbitrator.address,                 /* _arbitrator */
      [],                                 /* _arbitratorExtraData */
      constants.FEE_TIMEOUT,              /* _feeTimeout */
      platform,                           /* _feeRecipient */
      constants.FEE_RECIPIENT_BASISPOINT, /* _feeRecipientBasisPoint */
      whitelist                           /* _tokensWhitelist */
    ],
    log: true,
    deterministicDeployment: true
  });
};

export default func;
func.tags = ['NerwoEscrow'];
func.dependencies = ['NerwoCentralizedArbitrator'];
