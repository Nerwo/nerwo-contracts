import { expect } from 'chai';
import { deployments } from 'hardhat';

import { getContracts, getSigners } from '../utils';
import * as constants from '../../constants';

describe('NerwoEscrow: setTokensWhitelist', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('set whitelist', async () => {
    const { escrow, usdt } = await getContracts();
    const { deployer } = await getSigners();

    await escrow.connect(deployer).setTokensWhitelist(constants.getTokenWhitelist(usdt.address));
  });

  it('errors', async () => {
    const { escrow } = await getContracts();
    const { sender } = await getSigners();

    await expect(escrow.connect(sender).setTokensWhitelist([]))
      .to.be.revertedWith('Ownable: caller is not the owner');
  });
});
