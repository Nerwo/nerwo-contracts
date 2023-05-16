import { time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { deployments } from 'hardhat';

import * as constants from '../../constants';
import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: timeOutByReceiver', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'TetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('NoTimeout', async () => {
    const { arbitrator, escrow, usdt } = await getContracts();
    const { sender, receiver } = await getSigners();

    const amount = await randomAmount();
    const arbitrationPrice = await arbitrator.arbitrationCost([]);
    const transactionID = await createTransaction(sender, receiver.address, usdt, amount);

    await expect(escrow.connect(receiver).payArbitrationFeeByReceiver(
      transactionID, { value: arbitrationPrice }))
      .to.emit(escrow, 'HasToPayFee');

    await expect(escrow.connect(receiver).timeOutByReceiver(transactionID))
      .to.be.revertedWithCustomError(escrow, 'NoTimeout');
  });

  it('InvalidStatus', async () => {
    const { escrow, usdt } = await getContracts();
    const { sender, receiver } = await getSigners();

    const amount = await randomAmount();
    const transactionID = await createTransaction(sender, receiver.address, usdt, amount);

    await expect(escrow.connect(receiver).timeOutByReceiver(transactionID))
      .to.be.revertedWithCustomError(escrow, 'InvalidStatus');
  });

  it('Timeout', async () => {
    const { arbitrator, escrow, usdt } = await getContracts();
    const { platform, sender, receiver } = await getSigners();

    const amount = await randomAmount();
    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);
    const arbitrationPrice = await arbitrator.arbitrationCost([]);
    const transactionID = await createTransaction(sender, receiver.address, usdt, amount);

    await expect(escrow.connect(receiver).payArbitrationFeeByReceiver(
      transactionID, { value: arbitrationPrice }))
      .to.changeEtherBalances(
        [escrow, sender, receiver],
        [arbitrationPrice, 0, arbitrationPrice.mul(-1)]
      )
      .to.emit(escrow, 'HasToPayFee');

    await time.increase(constants.FEE_TIMEOUT);

    await expect(escrow.connect(receiver).timeOutByReceiver(transactionID))
      .to.changeEtherBalances(
        [escrow, platform, receiver],
        [arbitrationPrice.mul(-1), 0, arbitrationPrice]
      )
      .to.changeTokenBalances(
        usdt,
        [escrow, platform, sender, receiver],
        [amount.mul(-1), feeAmount, 0, amount.sub(feeAmount)]
      );
  });
});
