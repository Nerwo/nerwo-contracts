import { expect } from 'chai';
import { ethers } from 'hardhat';
import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';

import * as constants from '../constants';
import { deployFixture } from './fixtures';

describe('NerwoEscrow: executeTransaction', function () {
  async function createTransaction() {
    const { arbitrator, escrow, rogue } = await loadFixture(deployFixture);
    const [, platform, , sender, receiver] = await ethers.getSigners();
    const amount = ethers.utils.parseEther('0.02');
    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);

    const blockNumber = await ethers.provider.getBlockNumber();

    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT, receiver.address, '', { value: amount }))
      .to.changeEtherBalances(
        [platform, sender],
        [0, amount.mul(-1)]
      )
      .to.emit(escrow, 'TransactionCreated');

    const events = await escrow.queryFilter(escrow.filters.TransactionCreated(), blockNumber);
    expect(events).to.be.an('array').that.lengthOf(1);
    expect(events[0].args!).is.not.undefined;

    const { _transactionID } = events[0].args!;
    return { arbitrator, escrow, rogue, platform, sender, receiver, amount, feeAmount, _transactionID };
  }

  async function createDispute() {
    const { arbitrator, escrow, sender, receiver, _transactionID } = await loadFixture(createTransaction);
    const arbitrationPrice = await arbitrator.arbitrationCost([]);

    await expect(escrow.connect(sender).payArbitrationFeeBySender(
      _transactionID, { value: arbitrationPrice }))
      .to.emit(escrow, 'HasToPayFee');

    const blockNumber = await ethers.provider.getBlockNumber();

    await expect(await escrow.connect(receiver).payArbitrationFeeByReceiver(
      _transactionID, { value: arbitrationPrice }))
      .to.emit(escrow, 'Dispute')
      .to.not.emit(escrow, 'HasToPayFee');

    const dEvents = await escrow.queryFilter(escrow.filters.Dispute(), blockNumber);
    expect(dEvents).to.be.an('array').that.lengthOf(1);
    expect(dEvents[0].args!).is.not.undefined;
    let { _disputeID } = dEvents[0].args!;

    return { escrow, receiver, _transactionID, _disputeID };
  }

  it('NoTimeout', async () => {
    const { escrow, receiver, _transactionID } = await loadFixture(createTransaction);
    await expect(escrow.connect(receiver).executeTransaction(_transactionID))
      .to.be.revertedWithCustomError(escrow, 'NoTimeout');
  });

  it('InvalidAmount (already paid)', async () => {
    const { escrow, platform, sender, amount, feeAmount, _transactionID } = await loadFixture(createTransaction);

    await expect(escrow.connect(sender).pay(_transactionID, amount))
      .to.changeEtherBalances(
        [escrow, platform],
        [amount.mul(-1), feeAmount]
      )
      .to.emit(escrow, 'Payment').withArgs(_transactionID, amount, sender.address)
      .to.emit(escrow, 'FeeRecipientPayment');

    await time.increase(constants.TIMEOUT_PAYMENT);
    await expect(escrow.connect(sender).executeTransaction(_transactionID))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(0);
  });

  it('InvalidStatus', async () => {
    const { escrow, receiver, _transactionID } = await loadFixture(createDispute);

    await time.increase(constants.TIMEOUT_PAYMENT);
    await expect(escrow.connect(receiver).executeTransaction(_transactionID))
      .to.be.revertedWithCustomError(escrow, 'InvalidStatus');
  });


  it('FeeRecipientPayment', async () => {
    const { escrow, platform, receiver, amount, feeAmount, _transactionID } = await loadFixture(createTransaction);

    await time.increase(constants.TIMEOUT_PAYMENT);
    await expect(escrow.connect(receiver).executeTransaction(_transactionID))
      .to.changeEtherBalances(
        [escrow, platform, receiver],
        [amount.mul(-1), feeAmount, amount.sub(feeAmount)]
      )
      .to.emit(escrow, 'FeeRecipientPayment').withArgs(_transactionID, feeAmount);
  });
});
