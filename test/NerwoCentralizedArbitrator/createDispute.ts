import { expect } from 'chai';
import { deployments } from 'hardhat';

import { getContracts, getSigners } from '../utils';

describe('NerwoCentralizedArbitrator: createDispute', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('InvalidCaller', async () => {
    const { arbitrator } = await getContracts();
    const { sender } = await getSigners();

    const arbitrationPrice = await arbitrator.arbitrationCost('0x00');
    const choices = 2n;

    await expect(arbitrator.connect(sender).createDispute(choices, '0x00',
      { value: arbitrationPrice }))
      .to.be.revertedWithCustomError(arbitrator, 'InvalidCaller');
  });

  it('InsufficientPayment', async () => {
    const { arbitrator } = await getContracts();
    const { sender } = await getSigners();

    const arbitrationPrice = await arbitrator.arbitrationCost('0x00');
    const choices = 2n;

    // the amount is checked before the supportInterface
    await expect(arbitrator.connect(sender).createDispute(choices, '0x00'))
      .to.be.revertedWithCustomError(arbitrator, 'InsufficientPayment');
  });
});
