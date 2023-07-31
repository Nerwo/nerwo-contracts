import { expect } from 'chai';
import { deployments } from 'hardhat';

import { getContracts, getSigners, createTransaction, randomAmount, createNativeTransaction, NativeToken } from '../utils';

describe('NerwoEscrow: reimburse', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('reimbursing a transaction (ERC20)', async () => {
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
      .to.emit(escrow, 'Payment').withArgs(transactionID, freelancer.address, client.address, usdtAddress, partialAmount);

    await expect(escrow.connect(client).pay(transactionID, partialAmount))
      .to.changeTokenBalances(
        usdt,
        [escrow, platform, freelancer],
        [-partialAmount, feeAmount, partialAmount - feeAmount]
      )
      .to.emit(escrow, 'Payment').withArgs(transactionID, client.address, freelancer.address, usdtAddress, partialAmount)
      .to.emit(escrow, 'FeeRecipientPayment').withArgs(transactionID, platform.address, usdtAddress, feeAmount);

    await expect(escrow.connect(freelancer).reimburse(transactionID, partialAmount))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');
  });

  it('reimbursing a transaction (Native)', async () => {
    const { escrow, usdt } = await getContracts();
    const { platform, client, freelancer } = await getSigners();

    const amount = await randomAmount();
    const transactionID = await createNativeTransaction(client, freelancer.address, amount);

    await expect(escrow.connect(client).reimburse(transactionID, amount))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller');

    await expect(escrow.connect(freelancer).reimburse(transactionID, 0))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');

    await expect(escrow.connect(freelancer).reimburse(transactionID, amount * 2n))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');

    const partialAmount = amount / 2n;
    const feeAmount = await escrow.calculateFeeRecipientAmount(partialAmount);

    await expect(escrow.connect(freelancer).reimburse(transactionID, partialAmount))
      .to.changeEtherBalances(
        [escrow, client, freelancer],
        [-partialAmount, partialAmount, 0]
      )
      .to.emit(escrow, 'Payment').withArgs(transactionID, freelancer.address, client.address, NativeToken, partialAmount);

    await expect(escrow.connect(client).pay(transactionID, partialAmount))
      .to.changeEtherBalances(
        [escrow, platform, freelancer],
        [-partialAmount, feeAmount, partialAmount - feeAmount]
      )
      .to.emit(escrow, 'Payment').withArgs(transactionID, client.address, freelancer.address, NativeToken, partialAmount)
      .to.emit(escrow, 'FeeRecipientPayment').withArgs(transactionID, platform.address, NativeToken, feeAmount);

    await expect(escrow.connect(freelancer).reimburse(transactionID, partialAmount))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');
  });
});
