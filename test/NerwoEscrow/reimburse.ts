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
    const { platform, client, freelancer } = await getSigners();

    const amount = await randomAmount();
    const transactionID = await createTransaction(client, freelancer.address, usdt, amount);

    await expect(escrow.connect(client).reimburse(transactionID, amount))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller');

    await expect(escrow.connect(freelancer).reimburse(transactionID, 0))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');

    await expect(escrow.connect(freelancer).reimburse(transactionID, amount * 2n))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');

    const partialAmount = amount / 2n;
    const feeAmount = await escrow.calculateFeeRecipientAmount(partialAmount);

    const usdtAddress = await usdt.getAddress();

    await expect(escrow.connect(freelancer).reimburse(transactionID, partialAmount))
      .to.changeTokenBalances(
        usdt,
        [escrow, client, freelancer],
        [-partialAmount, partialAmount, 0]
      )
      .to.emit(escrow, 'Payment').withArgs(transactionID, usdtAddress, partialAmount, freelancer.address);

    await expect(escrow.connect(client).pay(transactionID, partialAmount))
      .to.changeTokenBalances(
        usdt,
        [escrow, platform, freelancer],
        [-partialAmount, feeAmount, partialAmount - feeAmount]
      )
      .to.emit(escrow, 'Payment').withArgs(transactionID, usdtAddress, partialAmount, client.address)
      .to.emit(escrow, 'FeeRecipientPayment').withArgs(transactionID, usdtAddress, feeAmount);

    await expect(escrow.connect(freelancer).reimburse(transactionID, partialAmount))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');
  });
});
