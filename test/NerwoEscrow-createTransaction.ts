import { expect } from 'chai';
import { ethers } from 'hardhat';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';

import * as constants from '../constants';
import { deployFixture } from './fixtures';

describe('NerwoEscrow: createTransaction', function () {
  it('Creating a transaction', async () => {
    const { escrow, sender, receiver } = await loadFixture(deployFixture);

    const amount = await escrow.minimalAmount();
    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT,
      receiver.address,
      '',
      { value: amount }))
      .to.changeEtherBalances(
        [escrow, sender],
        [amount, amount.mul(-1)]
      )
      .to.emit(escrow, 'TransactionCreated');
  });

  it('Creating a transaction with myself', async () => {
    const { escrow, sender } = await loadFixture(deployFixture);

    const amount = await escrow.minimalAmount();
    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT,
      sender.address,
      '',
      { value: amount })).to.be.revertedWithCustomError(escrow, 'InvalidCaller');
  });

  it('Creating a transaction with null receiver', async () => {
    const { escrow, sender } = await loadFixture(deployFixture);

    const amount = await escrow.minimalAmount();
    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT,
      constants.ZERO_ADDRESS,
      '',
      { value: amount })).to.be.revertedWithCustomError(escrow, 'NullAddress');
  });

  it('Creating a transaction < minimalAmount', async () => {
    const { escrow, sender, receiver } = await loadFixture(deployFixture);

    const minimalAmount = await escrow.minimalAmount();
    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT,
      receiver.address,
      '',
      { value: minimalAmount.sub(1) }))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(minimalAmount);
  });

  it('Creating a transaction with overflowing _timeoutPayment', async () => {
    const { escrow, sender, receiver } = await loadFixture(deployFixture);

    const amount = await escrow.minimalAmount();
    const timeoutPayment = ethers.BigNumber.from(2).pow(32);

    await expect(escrow.connect(sender).createTransaction(
      timeoutPayment,
      receiver.address,
      '',
      { value: amount }))
      .to.be.revertedWith(`SafeCast: value doesn't fit in 32 bits`);
  });

  it('Creating a transaction having b0rk3d priceThresholds', async () => {
    const { escrow, sender, receiver } = await loadFixture(deployFixture);

    const amount = await escrow.minimalAmount();

    await escrow.setPriceThresholds([
      {
        maxPrice: 0,
        feeBasisPoint: 0
      }
    ]);

    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT,
      receiver.address,
      '',
      { value: amount }))
      .to.be.revertedWithCustomError(escrow, 'InvalidPriceThresolds');
  });
});
