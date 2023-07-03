import { expect } from 'chai';
import { deployments } from 'hardhat';
import { parseEther } from 'ethers';

import { getContracts, getSigners } from '../utils';

describe('NerwoCentralizedArbitrator: setArbitrationPrice', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('Testing setArbitrationPrice', async () => {
    const { proxy } = await getContracts();
    const { client, deployer } = await getSigners();

    const arbitrationPrice = parseEther('0.005');

    await expect(proxy.connect(client).setArbitrationPrice(arbitrationPrice))
      .to.be.reverted;

    const previousPrice = await proxy.arbitrationCost('0x00');

    await expect(proxy.connect(deployer).setArbitrationPrice(arbitrationPrice))
      .to.emit(proxy, 'ArbitrationPriceChanged').withArgs(previousPrice, arbitrationPrice);
  });
});
