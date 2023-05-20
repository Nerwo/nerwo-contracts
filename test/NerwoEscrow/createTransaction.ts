import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';

import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: createTransaction', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('Creating a simple transaction', async () => {
    const { escrow, usdt } = await getContracts();
    const { sender, receiver } = await getSigners();

    const amount = await randomAmount();
    await createTransaction(sender, receiver.address, usdt, amount);
  });

  it('Creating a transaction with myself', async () => {
    const { escrow, usdt } = await getContracts();
    const { sender } = await getSigners();

    const amount = await randomAmount();
    await expect(createTransaction(sender, sender.address, usdt, amount))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller');
  });

  it('Creating a transaction with null receiver', async () => {
    const { escrow, usdt } = await getContracts();
    const { sender } = await getSigners();

    const amount = await randomAmount();
    await expect(createTransaction(sender, ethers.constants.AddressZero, usdt, amount))
      .to.be.revertedWithCustomError(escrow, 'NullAddress');
  });

  it('Creating a transaction with 0 amount', async () => {
    const { escrow, usdt } = await getContracts();
    const { sender, receiver } = await getSigners();

    await expect(createTransaction(sender, receiver.address, usdt))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(0);
  });

  it('InvalidToken', async () => {
    const { escrow } = await getContracts();
    const { sender, receiver } = await getSigners();

    const amount = await randomAmount();
    await expect(escrow.connect(sender).createTransaction(escrow.address, amount, receiver.address, ''))
      .to.be.revertedWithCustomError(escrow, 'InvalidToken');
  });
});
