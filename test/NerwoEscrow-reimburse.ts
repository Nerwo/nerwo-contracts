import { expect } from 'chai';
import { ethers } from 'hardhat';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';

import * as constants from '../constants';
import { deployAndFundRogueFixture, deployFixture } from './fixtures';

describe('NerwoEscrow: reimburse', function () {
  it('rogue as recipient', async () => {
    const { escrow, rogue, platform, sender } = await loadFixture(deployFixture);

    let amount = ethers.utils.parseEther('0.03');

    const blockNumber = await ethers.provider.getBlockNumber();
    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT, rogue.address, '', { value: amount }))
      .to.changeEtherBalances(
        [platform, sender],
        [0, amount.mul(-1)]
      )
      .to.emit(escrow, 'TransactionCreated');

    const events = await escrow.queryFilter(escrow.filters.TransactionCreated(), blockNumber);
    expect(events).to.be.an('array').that.lengthOf(1);
    expect(events[0].args!).is.not.undefined;

    const { _transactionID } = events[0].args!;

    await expect(escrow.connect(sender).reimburse(_transactionID, amount))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller').withArgs(rogue.address);

    await expect(rogue.reimburse(_transactionID, 0))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    await expect(rogue.reimburse(_transactionID, amount.mul(2)))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    amount = amount.div(2);
    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);

    await expect(rogue.reimburse(_transactionID, amount))
      .to.changeEtherBalances(
        [escrow, sender, rogue],
        [amount.mul(-1), amount, 0]
      )
      .to.emit(escrow, 'Payment').withArgs(_transactionID, amount, rogue.address);

    await rogue.setAction(constants.RogueAction.Reimburse);
    await rogue.setAmount(amount);
    await expect(escrow.connect(sender).pay(_transactionID, amount))
      .to.changeEtherBalances(
        [escrow, platform, rogue],
        [feeAmount.mul(-1), feeAmount, 0]
      )
      .to.emit(escrow, 'Payment').withArgs(_transactionID, amount, sender.address)
      .to.emit(escrow, 'FeeRecipientPayment').withArgs(_transactionID, feeAmount);

    await expect(rogue.reimburse(_transactionID, amount))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(0);
  });

  it('rogue as sender', async () => {
    const { escrow, rogue, platform, receiver } = await loadFixture(deployAndFundRogueFixture);

    let amount = ethers.utils.parseEther('0.02');
    await rogue.setAmount(amount);

    const blockNumber = await ethers.provider.getBlockNumber();
    await expect(rogue.createTransaction(
      constants.TIMEOUT_PAYMENT, receiver.address, ''))
      .to.changeEtherBalances(
        [platform, rogue],
        [0, amount.mul(-1)]
      )
      .to.emit(escrow, 'TransactionCreated');

    const events = await escrow.queryFilter(escrow.filters.TransactionCreated(), blockNumber);
    expect(events).to.be.an('array').that.lengthOf(1);
    expect(events[0].args!).is.not.undefined;

    const { _transactionID } = events[0].args!;

    await expect(rogue.pay(_transactionID, 0))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    await expect(rogue.reimburse(_transactionID, amount))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller').withArgs(receiver.address);

    await expect(escrow.connect(receiver).reimburse(_transactionID, 0))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    await expect(escrow.connect(receiver).reimburse(_transactionID, amount.mul(2)))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    amount = amount.div(2);
    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);

    await expect(escrow.connect(receiver).reimburse(_transactionID, amount))
      .to.changeEtherBalances(
        [escrow, rogue],
        [amount.mul(-1), amount]
      )
      .to.emit(escrow, 'Payment').withArgs(_transactionID, amount, receiver.address);

    await expect(rogue.pay(_transactionID, amount))
      .to.changeEtherBalances(
        [escrow, platform, rogue, receiver],
        [amount.mul(-1), feeAmount, 0, amount.sub(feeAmount)]
      )
      .to.emit(escrow, 'Payment').withArgs(_transactionID, amount, rogue.address)
      .to.emit(escrow, 'FeeRecipientPayment').withArgs(_transactionID, feeAmount);

    await expect(escrow.connect(receiver).reimburse(_transactionID, amount))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(0);
  });
});
