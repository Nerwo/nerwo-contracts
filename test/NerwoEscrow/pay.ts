import { expect } from 'chai';
import { deployments } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

import { NerwoEscrow, NerwoTetherToken } from '../../typechain-types';
import { getContracts, getSigners, createTransaction, randomAmount, createNativeTransaction } from '../utils';
import { ZeroAddress } from 'ethers';

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

    await expect(escrow.connect(client).pay(transactionID, 0))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');

    await expect(escrow.connect(client).pay(transactionID, amount * 2n))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');

    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);

    await expect(escrow.connect(client).pay(transactionID, amount))
      .to.changeTokenBalances(
        usdt,
        [escrow, platform, freelancer],
        [-amount, feeAmount, amount - feeAmount]
      )
      .to.emit(escrow, 'Payment').withArgs(transactionID, await usdt.getAddress(), amount, client.address)
      .to.emit(escrow, 'FeeRecipientPayment');
  });

  it('create a transaction and pay (Native)', async () => {
    let amount = await randomAmount();
    const transactionID = await createNativeTransaction(client, freelancer.address, amount);

    await expect(escrow.connect(client).pay(transactionID, 0))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');

    await expect(escrow.connect(client).pay(transactionID, amount * 2n))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');

    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);

    await expect(escrow.connect(client).pay(transactionID, amount))
      .to.changeEtherBalances(
        [escrow, platform, freelancer],
        [-amount, feeAmount, amount - feeAmount]
      )
      .to.emit(escrow, 'Payment').withArgs(transactionID, ZeroAddress, amount, client.address)
      .to.emit(escrow, 'FeeRecipientPayment');
  });
});
