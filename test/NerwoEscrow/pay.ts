import { expect } from 'chai';
import { deployments } from 'hardhat';

import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: pay', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('create a transaction and pay', async () => {
    const { escrow, usdt } = await getContracts();
    const { platform, sender, receiver } = await getSigners();

    let amount = await randomAmount();
    const _transactionID = await createTransaction(sender, receiver.address, usdt, amount);

    await expect(escrow.connect(sender).pay(_transactionID, 0))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    await expect(escrow.connect(sender).pay(_transactionID, amount.mul(2)))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);

    await expect(escrow.connect(sender).pay(_transactionID, amount))
      .to.changeTokenBalances(
        usdt,
        [escrow, platform, receiver],
        [amount.mul(-1), feeAmount, amount.sub(feeAmount)]
      )
      .to.emit(escrow, 'Payment').withArgs(_transactionID, usdt.address, amount, sender.address)
      .to.emit(escrow, 'FeeRecipientPayment');
  });
});
