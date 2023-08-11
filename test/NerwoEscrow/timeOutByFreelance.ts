import { expect } from 'chai';
import { deployments } from 'hardhat';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

import { NerwoEscrow, NerwoTetherToken } from '../../typechain-types';

import * as constants from '../../constants';
import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: timeOutByFreelancer', function () {
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

  let arbitrationPrice: bigint;

  beforeEach(async () => {
    ({ escrow, usdt } = await getContracts());
    ({ platform, client, freelancer } = await getSigners());
    arbitrationPrice = await escrow.getArbitrationCost();
  });

  it('NoTimeout', async () => {
    const amount = await randomAmount();
    const transactionID = await createTransaction(client, freelancer.address, usdt, amount);

    const tx = escrow.connect(freelancer).payArbitrationFee(transactionID, { value: arbitrationPrice });

    await expect(tx).to.emit(escrow, 'HasToPayFee')
      .withArgs(transactionID, client.address);

    await expect(escrow.connect(freelancer).timeOut(transactionID))
      .to.be.revertedWithCustomError(escrow, 'NoTimeout');
  });

  it('InvalidStatus', async () => {
    const amount = await randomAmount();
    const transactionID = await createTransaction(client, freelancer.address, usdt, amount);

    await time.increase(constants.FEE_TIMEOUT);

    await expect(escrow.connect(freelancer).timeOut(transactionID))
      .to.be.revertedWithCustomError(escrow, 'InvalidStatus');
  });

  it('Timeout', async () => {
    const amount = await randomAmount();
    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);
    const transactionID = await createTransaction(client, freelancer.address, usdt, amount);

    let tx = escrow.connect(freelancer).payArbitrationFee(transactionID, { value: arbitrationPrice });

    await expect(tx).to.changeEtherBalances(
      [escrow, client, freelancer],
      [arbitrationPrice, 0, -arbitrationPrice]
    );

    await expect(tx).to.emit(escrow, 'HasToPayFee')
      .withArgs(transactionID, client.address);

    await time.increase(constants.FEE_TIMEOUT);

    tx = escrow.connect(freelancer).timeOut(transactionID);

    await expect(tx).to.changeEtherBalances(
      [escrow, platform, freelancer],
      [-arbitrationPrice, 0, arbitrationPrice]
    );

    await expect(tx).to.changeTokenBalances(
      usdt,
      [escrow, platform, client, freelancer],
      [-amount, feeAmount, 0, amount - feeAmount]
    );
  });
});
