import { expect } from 'chai';
import { parseEther } from 'ethers';
import { deployments } from 'hardhat';

import { getContracts, getSigners } from '../utils';


describe('NerwoCentralizedArbitrator: setArbitrationPrice', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('Testing setArbitrationPrice', async () => {
    const { proxy } = await getContracts();
    const { client, court } = await getSigners();

    const arbitrationPrice = parseEther('0.005');

    await expect(proxy.connect(client).setArbitrationPrice(arbitrationPrice))
      .to.be.revertedWith('Ownable: caller is not the owner');

    const previousPrice = await proxy.arbitrationCost('0x00');

    await expect(proxy.connect(court).setArbitrationPrice(arbitrationPrice))
      .to.emit(proxy, 'ArbitrationPriceChanged').withArgs(previousPrice, arbitrationPrice);
  });
});
