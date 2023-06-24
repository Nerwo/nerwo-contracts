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
    const { platform, client, freelance } = await getSigners();

    let amount = await randomAmount();
    const _transactionID = await createTransaction(client, freelance.address, usdt, amount);

    await expect(escrow.connect(client).pay(_transactionID, 0))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');

    await expect(escrow.connect(client).pay(_transactionID, amount * 2n))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');

    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);

    await expect(escrow.connect(client).pay(_transactionID, amount))
      .to.changeTokenBalances(
        usdt,
        [escrow, platform, freelance],
        [-amount, feeAmount, amount - feeAmount]
      )
      .to.emit(escrow, 'Payment').withArgs(_transactionID, await usdt.getAddress(), amount, client.address)
      .to.emit(escrow, 'FeeRecipientPayment');
  });
});
