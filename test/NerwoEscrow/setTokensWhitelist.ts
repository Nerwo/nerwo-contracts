import { expect } from 'chai';
import { deployments } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

import { NerwoEscrow, NerwoTetherToken } from '../../typechain-types';

import { getContracts, getSigners } from '../utils';
import * as constants from '../../constants';

describe('NerwoEscrow: setTokensWhitelist', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  let escrow: NerwoEscrow;
  let usdt: NerwoTetherToken;

  let deployer: SignerWithAddress;
  let client: SignerWithAddress;

  beforeEach(async () => {
    ({ escrow, usdt } = await getContracts());
    ({ deployer, client } = await getSigners());
  });

  it('set whitelist', async () => {
    await escrow.connect(deployer).setTokensWhitelist(constants.getTokenWhitelist(await usdt.getAddress()));
  });

  it('errors', async () => {
    await expect(escrow.connect(client).setTokensWhitelist([]))
      .to.be.revertedWith('Ownable: caller is not the owner');
  });
});
