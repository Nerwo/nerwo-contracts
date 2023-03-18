import { expect } from 'chai';
import { parseEther } from 'ethers/lib/utils';
import { deployments } from 'hardhat';

import { getContracts, getSigners } from '../utils';

describe('NerwoCentralizedArbitrator: setArbitrationPrice', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'Rogue'], {
      keepExistingDeployments: true
    });
  });

  it('Testing setArbitrationPrice', async () => {
    const { arbitrator } = await getContracts();
    const { sender, court } = await getSigners();

    const arbitrationPrice = parseEther('0.005');

    await expect(arbitrator.connect(sender).setArbitrationPrice(arbitrationPrice))
      .to.be.revertedWith('Ownable: caller is not the owner');

    const previousPrice = await arbitrator.arbitrationCost([]);

    await expect(arbitrator.connect(court).setArbitrationPrice(arbitrationPrice))
      .to.emit(arbitrator, 'ArbitrationPriceChanged').withArgs(previousPrice, arbitrationPrice);
  });
});
