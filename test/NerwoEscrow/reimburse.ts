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

    let tx = escrow.connect(freelancer).reimburse(transactionID, partialAmount);

    await expect(tx).to.changeTokenBalances(
      usdt,
      [escrow, client, freelancer],
      [-partialAmount, partialAmount, 0]
    );

    await expect(tx).to.emit(escrow, 'Payment')
      .withArgs(transactionID, freelancer.address, client.address, usdtAddress, partialAmount);

    tx = escrow.connect(client).pay(transactionID, partialAmount);

    await expect(tx).to.changeTokenBalances(
      usdt,
      [escrow, platform, freelancer],
      [-partialAmount, feeAmount, partialAmount - feeAmount]
    );

    await expect(tx).to.emit(escrow, 'Payment')
      .withArgs(transactionID, client.address, freelancer.address, usdtAddress, partialAmount);

    await expect(tx).to.emit(escrow, 'FeeRecipientPayment')
      .withArgs(transactionID, platform.address, usdtAddress, feeAmount);

    await expect(escrow.connect(freelancer).reimburse(transactionID, partialAmount))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');
  });

  it('reimbursing a transaction (Native)', async () => {
    const { escrow } = await getContracts();
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

    let tx = escrow.connect(freelancer).reimburse(transactionID, partialAmount);

    await expect(tx).to.changeEtherBalances(
      [escrow, client, freelancer],
      [-partialAmount, partialAmount, 0]
    );

    await expect(tx).to.emit(escrow, 'Payment')
      .withArgs(transactionID, freelancer.address, client.address, NativeToken, partialAmount);

    tx = escrow.connect(client).pay(transactionID, partialAmount);

    await expect(tx).to.changeEtherBalances(
      [escrow, platform, freelancer],
      [-partialAmount, feeAmount, partialAmount - feeAmount]
    );

    await expect(tx).to.emit(escrow, 'Payment')
      .withArgs(transactionID, client.address, freelancer.address, NativeToken, partialAmount);

    await expect(tx).to.emit(escrow, 'FeeRecipientPayment')
      .withArgs(transactionID, platform.address, NativeToken, feeAmount);

    await expect(escrow.connect(freelancer).reimburse(transactionID, partialAmount))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');
  });
});
