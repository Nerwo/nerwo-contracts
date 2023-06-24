import { expect } from 'chai';
import { deployments } from 'hardhat';

import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';
import { ZeroAddress } from 'ethers';

describe('NerwoEscrow: createTransaction', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('Creating a simple transaction', async () => {
    const { usdt } = await getContracts();
    const { client, freelance } = await getSigners();

    const amount = await randomAmount();
    await createTransaction(client, freelance.address, usdt, amount);
  });

  it('Creating a transaction with myself', async () => {
    const { escrow, usdt } = await getContracts();
    const { client } = await getSigners();

    const amount = await randomAmount();
    await expect(createTransaction(client, client.address, usdt, amount))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller');
  });

  it('Creating a transaction with null freelance', async () => {
    const { escrow, usdt } = await getContracts();
    const { client } = await getSigners();

    const amount = await randomAmount();
    await expect(createTransaction(client, ZeroAddress, usdt, amount))
      .to.be.revertedWithCustomError(escrow, 'NullAddress');
  });

  it('Creating a transaction with 0 amount', async () => {
    const { escrow, usdt } = await getContracts();
    const { client, freelance } = await getSigners();

    await expect(createTransaction(client, freelance.address, usdt))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');
  });

  it('InvalidToken', async () => {
    const { escrow } = await getContracts();
    const { client, freelance } = await getSigners();

    const amount = await randomAmount();
    await expect(escrow.connect(client).createTransaction(await escrow.getAddress(), amount, freelance.address))
      .to.be.revertedWithCustomError(escrow, 'InvalidToken');
  });
});
