import { expect } from 'chai';
import { deployments } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

import { NerwoEscrow, NerwoTetherToken } from '../../typechain-types';
import { getContracts, getSigners, createTransaction, randomAmount, createNativeTransaction, NativeToken } from '../utils';

describe('NerwoEscrow: pay', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  let escrow: NerwoEscrow;
  let usdt: NerwoTetherToken;

  let platform: SignerWithAddress;
  let client: SignerWithAddress;
  let freelancer: SignerWithAddress;

  beforeEach(async () => {
    ({ escrow, usdt } = await getContracts());
    ({ platform, client, freelancer } = await getSigners());
  });

  it('create a transaction and pay (ERC20)', async () => {
    let amount = await randomAmount();
    const transactionID = await createTransaction(client, freelancer.address, usdt, amount);

    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);

    const tx = escrow.connect(client).pay(transactionID);

    await expect(tx).to.changeTokenBalances(
      usdt,
      [escrow, platform, freelancer],
      [-amount, feeAmount, amount - feeAmount]
    );

    await expect(tx).to.emit(escrow, 'Payment')
      .withArgs(transactionID, client.address, freelancer.address, await usdt.getAddress(), amount - feeAmount);

    await expect(tx).to.emit(escrow, 'FeeRecipientPayment');

    await expect(escrow.connect(client).pay(transactionID))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');
  });

  it('create a transaction and pay (Native)', async () => {
    let amount = await randomAmount();
    const transactionID = await createNativeTransaction(client, freelancer.address, amount);

    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);

    const tx = escrow.connect(client).pay(transactionID);

    await expect(tx).to.changeEtherBalances(
      [escrow, platform, freelancer],
      [-amount, feeAmount, amount - feeAmount]
    );

    await expect(tx).to.emit(escrow, 'Payment')
      .withArgs(transactionID, client.address, freelancer.address, NativeToken, amount - feeAmount);

    await expect(tx).to.emit(escrow, 'FeeRecipientPayment');

    await expect(escrow.connect(client).pay(transactionID))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');
  });
});
