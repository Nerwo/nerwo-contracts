import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';

import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: createTransaction', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'TetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('Creating a simple transaction', async () => {
    const { usdt } = await getContracts();
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

  it('Creating a transaction < minimalAmount', async () => {
    const { escrow, usdt } = await getContracts();
    const { sender, receiver } = await getSigners();

    const minimalAmount = await escrow.minimalAmount();
    await expect(createTransaction(sender, receiver.address, usdt, minimalAmount.sub(1)))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(minimalAmount);
  });
});
