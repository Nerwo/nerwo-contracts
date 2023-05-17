import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { deployments } from 'hardhat';

import { getContracts, getSigners } from '../utils';

describe('NerwoCentralizedArbitrator: createDispute', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'TetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('InvalidCaller', async () => {
    const { arbitrator } = await getContracts();
    const { sender } = await getSigners();

    const arbitrationPrice = await arbitrator.arbitrationCost([]);
    const choices = BigNumber.from(2);

    await expect(arbitrator.connect(sender).createDispute(choices, [],
      { value: arbitrationPrice }))
      .to.be.revertedWithCustomError(arbitrator, 'InvalidCaller');
  });

  it('InsufficientPayment', async () => {
    const { arbitrator } = await getContracts();
    const { sender } = await getSigners();

    const arbitrationPrice = await arbitrator.arbitrationCost([]);
    const choices = BigNumber.from(2);

    // the amount is checked before the supportInterface
    await expect(arbitrator.connect(sender).createDispute(choices, []))
      .to.be.revertedWithCustomError(arbitrator, 'InsufficientPayment')
      .withArgs(0, arbitrationPrice);
  });
});
