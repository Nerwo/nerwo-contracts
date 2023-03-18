import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';

import * as constants from '../../constants';
import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: createTransaction', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'Rogue'], {
      keepExistingDeployments: true
    });
  });

  it('Creating a transaction', async () => {
    const { escrow } = await getContracts();
    const { sender, receiver } = await getSigners();

    const amount = await randomAmount();
    await createTransaction(sender, receiver.address, amount);
  });

  it('Creating a transaction with myself', async () => {
    const { escrow } = await getContracts();
    const { sender, receiver } = await getSigners();

    const amount = await randomAmount();
    await expect(createTransaction(sender, sender.address, amount))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller');
  });

  it('Creating a transaction with null receiver', async () => {
    const { escrow } = await getContracts();
    const { sender } = await getSigners();

    const amount = await randomAmount();
    await expect(createTransaction(sender, ethers.constants.AddressZero, amount))
      .to.be.revertedWithCustomError(escrow, 'NullAddress');
  });

  it('Creating a transaction < minimalAmount', async () => {
    const { escrow } = await getContracts();
    const { sender, receiver } = await getSigners();

    const minimalAmount = await escrow.minimalAmount();
    await expect(createTransaction(sender, receiver.address, minimalAmount.sub(1)))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(minimalAmount);
  });

  it('Creating a transaction with overflowing _timeoutPayment', async () => {
    const { escrow } = await getContracts();
    const { sender, receiver } = await getSigners();

    const amount = await randomAmount();
    const timeoutPayment = ethers.BigNumber.from(2).pow(32);

    await expect(createTransaction(sender, receiver.address, amount, timeoutPayment))
      .to.be.revertedWith(`SafeCast: value doesn't fit in 32 bits`);
  });

  it('Creating a transaction having b0rk3d priceThresholds', async () => {
    const { escrow } = await getContracts();
    const { deployer, sender, receiver } = await getSigners();

    const amount = await randomAmount();

    await escrow.setPriceThresholds([{
      maxPrice: 0,
      feeBasisPoint: 0
    }]);

    await expect(createTransaction(sender, receiver.address, amount))
      .to.be.revertedWithCustomError(escrow, 'InvalidPriceThresolds');

    // reset back to original
    await escrow.connect(deployer).setPriceThresholds(constants.FEE_PRICE_THRESHOLDS);
  });
});
