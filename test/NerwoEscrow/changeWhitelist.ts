import { expect } from 'chai';
import { deployments } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

import { NerwoEscrow, NerwoTetherToken } from '../../typechain-types';

import { getContracts, getSigners } from '../utils';
import * as constants from '../../constants';

describe('NerwoEscrow: changeWhitelist', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  let escrow: NerwoEscrow;
  let usdt: NerwoTetherToken;

  let platform: SignerWithAddress;
  let client: SignerWithAddress;

  beforeEach(async () => {
    ({ escrow, usdt } = await getContracts());
    ({ platform, client } = await getSigners());
  });

  it('change whitelist', async () => {
    await escrow.connect(platform).changeWhitelist(constants.getTokenWhitelist(await usdt.getAddress()));
  });

  it('errors', async () => {
    await expect(escrow.connect(client).changeWhitelist([]))
      .to.be.revertedWith('Ownable: caller is not the owner');
  });
});
