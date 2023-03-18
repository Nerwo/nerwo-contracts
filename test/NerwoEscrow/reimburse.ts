import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';
import { anyUint } from '@nomicfoundation/hardhat-chai-matchers/withArgs';

import * as constants from '../../constants';
import { getContracts, getSigners, fund, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: reimburse', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'Rogue'], {
      keepExistingDeployments: true
    });
  });

  it('rogue as recipient', async () => {
    const { escrow, rogue } = await getContracts();
    const { platform, sender } = await getSigners();

    let amount = ethers.utils.parseEther('0.02');
    const transactionID = await createTransaction(sender, rogue.address, amount);

    await expect(escrow.connect(sender).reimburse(transactionID, amount))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller').withArgs(rogue.address);

    await expect(rogue.reimburse(transactionID, 0))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    await expect(rogue.reimburse(transactionID, amount.mul(2)))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    amount = amount.div(2);
    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);

    await expect(rogue.reimburse(transactionID, amount))
      .to.changeEtherBalances(
        [escrow, sender, rogue],
        [amount.mul(-1), amount, 0]
      )
      .to.emit(escrow, 'Payment').withArgs(transactionID, amount, rogue.address);

    await rogue.setAmount(amount);

    await rogue.setAction(constants.RogueAction.Reimburse);
    await expect(escrow.connect(sender).pay(transactionID, amount))
      .to.changeEtherBalances(
        [escrow, platform, rogue],
        [feeAmount.mul(-1), feeAmount, 0]
      )
      .to.emit(escrow, 'Payment').withArgs(transactionID, amount, sender.address)
      .to.emit(escrow, 'FeeRecipientPayment').withArgs(transactionID, feeAmount);
    await rogue.setAction(constants.RogueAction.None);

    await expect(rogue.reimburse(transactionID, amount))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(0);
  });

  it('rogue as sender', async () => {
    const { escrow, rogue } = await getContracts();
    const { receiver } = await getSigners();

    await fund(rogue, ethers.utils.parseEther('10.0'));

    let amount = await randomAmount();
    await rogue.setAmount(amount);

    const blockNumber = await ethers.provider.getBlockNumber();

    // check balance b0rk3d when calling a contract that sends ether
    await rogue.createTransaction(constants.TIMEOUT_PAYMENT, receiver.address, '', { value: amount });

    const events = await escrow.queryFilter(escrow.filters.TransactionCreated(), blockNumber);
    expect(events).to.be.an('array');
    expect(events.at(-1)?.args?._transactionID).is.not.undefined;

    const transactionID = events.at(-1)!.args!._transactionID!;

    await expect(rogue.pay(transactionID, 0))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    await expect(rogue.reimburse(transactionID, amount))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller').withArgs(receiver.address);

    await expect(escrow.connect(receiver).reimburse(transactionID, 0))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    await expect(escrow.connect(receiver).reimburse(transactionID, amount.mul(2)))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    amount = amount.div(2);

    await expect(escrow.connect(receiver).reimburse(transactionID, amount))
      .to.changeEtherBalances(
        [escrow, rogue],
        [amount.mul(-1), amount]
      )
      .to.emit(escrow, 'Payment').withArgs(transactionID, amount, receiver.address);

    const { feeBasisPoint } = await escrow.transactions(transactionID);
    const feeAmount = amount.mul(feeBasisPoint).div(10000);

    // check balance b0rk3d when calling a contract that sends ether
    await expect(rogue.pay(transactionID, amount))
      .to.emit(escrow, 'Payment').withArgs(transactionID, amount, rogue.address)
      .to.emit(escrow, 'FeeRecipientPayment').withArgs(transactionID, feeAmount);

    await expect(escrow.connect(receiver).reimburse(transactionID, amount))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(0);
  });
});
