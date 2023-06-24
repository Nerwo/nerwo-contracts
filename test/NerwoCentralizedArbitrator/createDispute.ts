import { expect } from 'chai';
import { deployments } from 'hardhat';

import { getContracts, getSigners } from '../utils';

describe('NerwoCentralizedproxy: createDispute', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('InsufficientPayment', async () => {
    const { proxy } = await getContracts();
    const { client } = await getSigners();

    const arbitrationPrice = await proxy.arbitrationCost('0x00');
    const choices = 2n;

    // the amount is checked before the supportInterface
    await expect(proxy.connect(client)['createDispute(bytes,string,uint256)']('0x00', '', choices))
      .to.be.revertedWithCustomError(proxy, 'InsufficientPayment');
  });
});
