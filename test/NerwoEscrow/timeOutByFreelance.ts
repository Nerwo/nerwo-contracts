import { expect } from 'chai';
import { deployments } from 'hardhat';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

import { NerwoEscrow, NerwoTetherToken } from '../../typechain-types';

import * as constants from '../../constants';
import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: timeOutByFreelance', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  let escrow: NerwoEscrow;
  let usdt: NerwoTetherToken;

  let platform: SignerWithAddress;
  let client: SignerWithAddress;
  let freelance: SignerWithAddress;

  let arbitrationPrice: bigint;

  beforeEach(async () => {
    ({ escrow, usdt } = await getContracts());
    ({ platform, client, freelance } = await getSigners());
    arbitrationPrice = await escrow.getArbitrationCost();
  });

  it('NoTimeout', async () => {
    const amount = await randomAmount();
    const transactionID = await createTransaction(client, freelance.address, usdt, amount);

    await expect(escrow.connect(freelance).payArbitrationFee(
      transactionID, { value: arbitrationPrice }))
      .to.emit(escrow, 'HasToPayFee')
      .withArgs(transactionID, client.address);

    await expect(escrow.connect(freelance).timeOut(transactionID))
      .to.be.revertedWithCustomError(escrow, 'NoTimeout');
  });

  it('InvalidStatus', async () => {
    const amount = await randomAmount();
    const transactionID = await createTransaction(client, freelance.address, usdt, amount);

    await time.increase(constants.FEE_TIMEOUT);

    await expect(escrow.connect(freelance).timeOut(transactionID))
      .to.be.revertedWithCustomError(escrow, 'InvalidStatus');
  });

  it('Timeout', async () => {
    const amount = await randomAmount();
    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);
    const transactionID = await createTransaction(client, freelance.address, usdt, amount);

    await expect(escrow.connect(freelance).payArbitrationFee(
      transactionID, { value: arbitrationPrice }))
      .to.changeEtherBalances(
        [escrow, client, freelance],
        [arbitrationPrice, 0, -arbitrationPrice]
      )
      .to.emit(escrow, 'HasToPayFee')
      .withArgs(transactionID, client.address);

    await time.increase(constants.FEE_TIMEOUT);

    await expect(escrow.connect(freelance).timeOut(transactionID))
      .to.changeEtherBalances(
        [escrow, platform, freelance],
        [-arbitrationPrice, 0, arbitrationPrice]
      )
      .to.changeTokenBalances(
        usdt,
        [escrow, platform, client, freelance],
        [-amount, feeAmount, 0, amount - feeAmount]
      );
  });
});
