import { time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { deployments } from 'hardhat';

import * as constants from '../../constants';
import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: timeOutBySender', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('NoTimeout', async () => {
    const { escrow, usdt } = await getContracts();
    const { sender, receiver } = await getSigners();

    const amount = await randomAmount();
    const arbitrationPrice = await escrow.arbitrationCost();
    const transactionID = await createTransaction(sender, receiver.address, usdt, amount);

    await expect(escrow.connect(sender).payArbitrationFeeBySender(
      transactionID, { value: arbitrationPrice }))
      .to.emit(escrow, 'HasToPayFee');

    await expect(escrow.connect(sender).timeOutBySender(transactionID))
      .to.be.revertedWithCustomError(escrow, 'NoTimeout');
  });

  it('InvalidStatus', async () => {
    const { escrow, usdt } = await getContracts();
    const { sender, receiver } = await getSigners();

    const amount = await randomAmount();
    const transactionID = await createTransaction(sender, receiver.address, usdt, amount);

    await expect(escrow.connect(sender).timeOutBySender(transactionID))
      .to.be.revertedWithCustomError(escrow, 'InvalidStatus');
  });

  it('Timeout', async () => {
    const { escrow, usdt } = await getContracts();
    const { sender, receiver } = await getSigners();

    const amount = await randomAmount();
    const arbitrationPrice = await escrow.arbitrationCost();
    const transactionID = await createTransaction(sender, receiver.address, usdt, amount);

    await expect(escrow.connect(sender).payArbitrationFeeBySender(
      transactionID, { value: arbitrationPrice }))
      .to.changeEtherBalances(
        [escrow, sender],
        [arbitrationPrice, -arbitrationPrice]
      )
      .to.emit(escrow, 'HasToPayFee');

    await time.increase(constants.FEE_TIMEOUT);

    await expect(escrow.connect(sender).timeOutBySender(transactionID))
      .to.changeEtherBalances(
        [escrow, sender, receiver],
        [-arbitrationPrice, arbitrationPrice, 0]
      )
      .to.changeTokenBalances(
        usdt,
        [escrow, sender, receiver],
        [-amount, amount, 0]
      );
  });
});
