import { expect } from 'chai';
import { deployments } from 'hardhat';

import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: reimburse', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('reimbursing a transaction', async () => {
    const { escrow, usdt } = await getContracts();
    const { platform, sender, receiver } = await getSigners();

    const amount = await randomAmount();
    const transactionID = await createTransaction(sender, receiver.address, usdt, amount);

    await expect(escrow.connect(sender).reimburse(transactionID, amount))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller').withArgs(receiver.address);

    await expect(escrow.connect(receiver).reimburse(transactionID, 0))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');

    await expect(escrow.connect(receiver).reimburse(transactionID, amount * 2n))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');

    const partialAmount = amount / 2n;
    const feeAmount = await escrow.calculateFeeRecipientAmount(partialAmount);

    await expect(escrow.connect(receiver).reimburse(transactionID, partialAmount))
      .to.changeTokenBalances(
        usdt,
        [escrow, sender, receiver],
        [-partialAmount, partialAmount, 0]
      )
      .to.emit(escrow, 'Payment').withArgs(transactionID, (await usdt.getAddress()), partialAmount, receiver.address);

    await expect(escrow.connect(sender).pay(transactionID, partialAmount))
      .to.changeTokenBalances(
        usdt,
        [escrow, platform, receiver],
        [-partialAmount, feeAmount, partialAmount - feeAmount]
      )
      .to.emit(escrow, 'Payment').withArgs(transactionID, (await usdt.getAddress()), partialAmount, sender.address)
      .to.emit(escrow, 'FeeRecipientPayment').withArgs(transactionID, (await usdt.getAddress()), feeAmount);

    await expect(escrow.connect(receiver).reimburse(transactionID, partialAmount))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');
  });
});
