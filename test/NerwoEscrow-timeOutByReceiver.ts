import { expect } from 'chai';
import { ethers } from 'hardhat';
import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';

import * as constants from '../constants';
import { deployFixture } from './fixtures';

describe('NerwoEscrow: timeOutByReceiver', function () {
  async function createTransaction() {
    const { arbitrator, escrow, platform, sender, receiver } = await loadFixture(deployFixture);

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
    return { arbitrator, escrow, platform, sender, receiver, amount, feeAmount, _transactionID };
  }

  it('NoTimeout', async () => {
    const { arbitrator, escrow, receiver, _transactionID } = await loadFixture(createTransaction);
    const arbitrationPrice = await arbitrator.arbitrationCost([]);

    await expect(escrow.connect(receiver).payArbitrationFeeByReceiver(
      _transactionID, { value: arbitrationPrice }))
      .to.emit(escrow, 'HasToPayFee');

    await expect(escrow.connect(receiver).timeOutByReceiver(_transactionID))
      .to.be.revertedWithCustomError(escrow, 'NoTimeout');
  });

  it('InvalidStatus', async () => {
    const { escrow, receiver, _transactionID } = await loadFixture(createTransaction);

    await expect(escrow.connect(receiver).timeOutByReceiver(_transactionID))
      .to.be.revertedWithCustomError(escrow, 'InvalidStatus');
  });

  it('Timeout', async () => {
    const { arbitrator, escrow, platform, receiver, amount, feeAmount, _transactionID }
      = await loadFixture(createTransaction);
    const arbitrationPrice = await arbitrator.arbitrationCost([]);

    await expect(escrow.connect(receiver).payArbitrationFeeByReceiver(
      _transactionID, { value: arbitrationPrice }))
      .to.changeEtherBalances(
        [escrow, receiver],
        [arbitrationPrice, arbitrationPrice.mul(-1)]
      )
      .to.emit(escrow, 'HasToPayFee');

    await time.increase(constants.FEE_TIMEOUT);

    await expect(escrow.connect(receiver).timeOutByReceiver(_transactionID))
      .to.changeEtherBalances(
        [escrow, platform, receiver],
        [amount.add(arbitrationPrice).mul(-1), feeAmount, amount.sub(feeAmount).add(arbitrationPrice)]
      );
  });
});
