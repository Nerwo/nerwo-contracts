import { expect } from 'chai';
import { ZeroAddress } from 'ethers';
import { deployments } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

import { NerwoEscrow, NerwoTetherToken } from '../../typechain-types';
import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: createTransaction', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  let escrow: NerwoEscrow;
  let usdt: NerwoTetherToken;

  let client: SignerWithAddress;
  let freelance: SignerWithAddress;

  beforeEach(async () => {
    ({ escrow, usdt } = await getContracts());
    ({ client, freelance } = await getSigners());
  });

  it('Creating a simple transaction', async () => {
    const amount = await randomAmount();
    await createTransaction(client, freelance.address, usdt, amount);
  });

  it('Creating a transaction with myself', async () => {
     const amount = await randomAmount();
    await expect(createTransaction(client, client.address, usdt, amount))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller');
  });

  it('Creating a transaction with null freelance', async () => {
    const amount = await randomAmount();
    await expect(createTransaction(client, ZeroAddress, usdt, amount))
      .to.be.revertedWithCustomError(escrow, 'NullAddress');
  });

  it('Creating a transaction with 0 amount', async () => {
    await expect(createTransaction(client, freelance.address, usdt))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');
  });

  it('InvalidToken', async () => {
    const amount = await randomAmount();
    await expect(escrow.connect(client).createTransaction(await escrow.getAddress(), amount, freelance.address))
      .to.be.revertedWithCustomError(escrow, 'InvalidToken');
  });
});
