import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { NerwoEscrowV1 } from '../typechain-types';

import * as constants from '../constants';

describe('NerwoEscrow: createTransaction', function () {
  let escrow: NerwoEscrowV1;
  let deployer: SignerWithAddress, sender: SignerWithAddress, receiver: SignerWithAddress;

  this.beforeEach(async () => {
    [deployer, , , sender, receiver] = await ethers.getSigners();

    await deployments.fixture(['NerwoCentralizedArbitratorV1', 'NerwoEscrowV1'], {
      keepExistingDeployments: true
    });

    let deployment = await deployments.get('NerwoEscrowV1');
    escrow = await ethers.getContractAt('NerwoEscrowV1', deployment.address);
  });

  it('Creating a transaction', async () => {
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
    const amount = await escrow.minimalAmount();
    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT,
      sender.address,
      '',
      { value: amount })).to.be.revertedWithCustomError(escrow, 'InvalidCaller');
  });

  it('Creating a transaction with null receiver', async () => {
    const amount = await escrow.minimalAmount();
    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT,
      constants.ZERO_ADDRESS,
      '',
      { value: amount })).to.be.revertedWithCustomError(escrow, 'NullAddress');
  });

  it('Creating a transaction < minimalAmount', async () => {
    const minimalAmount = await escrow.minimalAmount();
    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT,
      receiver.address,
      '',
      { value: minimalAmount.sub(1) }))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(minimalAmount);
  });

  it('Creating a transaction with overflowing _timeoutPayment', async () => {
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
