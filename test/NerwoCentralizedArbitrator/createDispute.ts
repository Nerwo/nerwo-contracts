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

    await expect(proxy.connect(client)['createDispute(bytes,string,uint256)']('0x00', '', 2n))
      .to.be.revertedWithCustomError(proxy, 'InsufficientPayment');
  });
});
