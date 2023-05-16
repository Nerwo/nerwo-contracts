import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';
import { anyUint } from '@nomicfoundation/hardhat-chai-matchers/withArgs';

import { getContracts, getSigners, fund, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: reimburse', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'TetherToken'], {
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
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    await expect(escrow.connect(receiver).reimburse(transactionID, amount.mul(2)))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    const partialAmount = amount.div(2);
    const feeAmount = await escrow.calculateFeeRecipientAmount(partialAmount);

    await expect(escrow.connect(receiver).reimburse(transactionID, partialAmount))
      .to.changeTokenBalances(
        usdt,
        [escrow, sender, receiver],
        [partialAmount.mul(-1), partialAmount, 0]
      )
      .to.emit(escrow, 'Payment').withArgs(transactionID, usdt.address, partialAmount, receiver.address);

    await expect(escrow.connect(sender).pay(transactionID, partialAmount))
      .to.changeTokenBalances(
        usdt,
        [escrow, platform, receiver],
        [partialAmount.mul(-1), feeAmount, partialAmount.sub(feeAmount)]
      )
      .to.emit(escrow, 'Payment').withArgs(transactionID, usdt.address, partialAmount, sender.address)
      .to.emit(escrow, 'FeeRecipientPayment').withArgs(transactionID, usdt.address, feeAmount);

    await expect(escrow.connect(receiver).reimburse(transactionID, partialAmount))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(0);
  });
});
