import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';
import { time } from '@nomicfoundation/hardhat-network-helpers';

import * as constants from '../constants';
import { getContracts, getSigners, createTransaction, createDispute, randomAmount } from './utils';

describe('NerwoEscrow: executeTransaction', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'Rogue'], {
      keepExistingDeployments: true
    });
  });

  it('NoTimeout', async () => {
    const { escrow } = await getContracts();
    const { sender, receiver } = await getSigners();

    const amount = await randomAmount();
    const transactionID = await createTransaction(sender, receiver.address, amount);

    await expect(escrow.connect(receiver).executeTransaction(transactionID))
      .to.be.revertedWithCustomError(escrow, 'NoTimeout');
  });

  it('InvalidAmount (already paid)', async () => {
    const { escrow } = await getContracts();
    const { platform, sender, receiver } = await getSigners();

    const amount = ethers.utils.parseEther('0.02');
    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);
    const transactionID = await createTransaction(sender, receiver.address, amount);

    expect(await escrow.connect(sender).pay(transactionID, amount))
      .to.changeEtherBalances(
        [escrow, platform],
        [amount.mul(-1), feeAmount]
      )
      .to.emit(escrow, 'Payment').withArgs(transactionID, amount, sender.address)
      .to.emit(escrow, 'FeeRecipientPayment');

    await time.increase(constants.TIMEOUT_PAYMENT);
    await expect(escrow.connect(sender).executeTransaction(transactionID))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(0);
  });

  it('InvalidStatus', async () => {
    const { escrow } = await getContracts();
    const { sender, receiver } = await getSigners();

    const amount = ethers.utils.parseEther('0.02');
    let transactionID = await createTransaction(sender, receiver.address, amount);
    await createDispute(sender, receiver, transactionID);

    await time.increase(constants.TIMEOUT_PAYMENT);
    await expect(escrow.connect(receiver).executeTransaction(transactionID))
      .to.be.revertedWithCustomError(escrow, 'InvalidStatus');
  });

  it('ReentrancyGuard', async () => {
    const { escrow, rogue } = await getContracts();
    const { platform, sender } = await getSigners();

    const amount = ethers.utils.parseEther('0.02');
    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);
    const transactionID = await createTransaction(sender, rogue.address, amount);

    await rogue.setTransaction(transactionID);
    await rogue.setFailOnError(false);

    await time.increase(constants.TIMEOUT_PAYMENT);

    await rogue.setAction(constants.RogueAction.ExecuteTransaction);
    expect(await escrow.connect(sender).executeTransaction(transactionID))
      .to.changeEtherBalances(
        [escrow, rogue, platform],
        [amount.mul(-1), amount.sub(feeAmount), feeAmount]
      )
      .to.emit(rogue, 'ErrorNotHandled').withArgs('ReentrancyGuard: reentrant call');
    await rogue.setAction(constants.RogueAction.None);
  });

  it('FeeRecipientPayment', async () => {
    const { escrow } = await getContracts();
    const { platform, sender, receiver } = await getSigners();

    const amount = ethers.utils.parseEther('0.02');
    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);
    const transactionID = await createTransaction(sender, receiver.address, amount);

    await time.increase(constants.TIMEOUT_PAYMENT);
    expect(await escrow.connect(receiver).executeTransaction(transactionID))
      .to.changeEtherBalances(
        [escrow, platform, receiver],
        [amount.mul(-1), feeAmount, amount.sub(feeAmount)]
      )
      .to.emit(escrow, 'FeeRecipientPayment').withArgs(transactionID, feeAmount);
  });
});
