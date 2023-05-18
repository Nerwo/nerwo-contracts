import { expect } from 'chai';
import { deployments } from 'hardhat';

import { getContracts, getSigners } from '../utils';

describe('NerwoEscrow: setTokensWhitelist', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('set whitelist', async () => {
    const { escrow, usdt } = await getContracts();
    const { deployer } = await getSigners();

    await escrow.connect(deployer).setTokensWhitelist([usdt.address]);
  });

  it('errors', async () => {
    const { escrow, } = await getContracts();
    const { deployer, sender } = await getSigners();

    await expect(escrow.connect(sender).setTokensWhitelist([]))
      .to.be.revertedWith('Ownable: caller is not the owner');

    await expect(escrow.connect(deployer).setTokensWhitelist([]))
      .to.be.revertedWithCustomError(escrow, 'InvalidToken');
  });
});
