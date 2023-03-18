import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { deployments } from 'hardhat';

import { getContracts, getSigners } from '../utils';

describe('NerwoCentralizedArbitrator: createDispute', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'Rogue'], {
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

  it('InsufficientFunding', async () => {
    const { arbitrator } = await getContracts();
    const { sender } = await getSigners();

    const arbitrationPrice = await arbitrator.arbitrationCost([]);
    const choices = BigNumber.from(2);

    await expect(arbitrator.connect(sender).createDispute(choices, []))
      .to.be.revertedWithCustomError(arbitrator, 'InsufficientFunding')
      .withArgs(arbitrationPrice);
  });
});
