import { time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { deployments } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

import { NerwoEscrow, NerwoTetherToken } from '../../typechain-types';

import * as constants from '../../constants';
import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: timeOutByClient', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  let escrow: NerwoEscrow;
  let usdt: NerwoTetherToken;

  let client: SignerWithAddress;
  let freelancer: SignerWithAddress;

  let arbitrationPrice: bigint;

  beforeEach(async () => {
    ({ escrow, usdt } = await getContracts());
    ({ client, freelancer } = await getSigners());
    arbitrationPrice = await escrow.getArbitrationCost();
  });

  it('NoTimeout', async () => {
    const amount = await randomAmount();
    const transactionID = await createTransaction(client, freelancer.address, usdt, amount);

    await expect(escrow.connect(client).payArbitrationFee(
      transactionID, { value: arbitrationPrice }))
      .to.emit(escrow, 'HasToPayFee')
      .withArgs(transactionID, freelancer.address);

    await expect(escrow.connect(client).timeOut(transactionID))
      .to.be.revertedWithCustomError(escrow, 'NoTimeout');
  });

  it('InvalidStatus', async () => {
    const amount = await randomAmount();
    const transactionID = await createTransaction(client, freelancer.address, usdt, amount);

    await time.increase(constants.FEE_TIMEOUT);

    await expect(escrow.connect(client).timeOut(transactionID))
      .to.be.revertedWithCustomError(escrow, 'InvalidStatus');
  });

  it('Timeout', async () => {
    const amount = await randomAmount();
    const transactionID = await createTransaction(client, freelancer.address, usdt, amount);

    await expect(escrow.connect(client).payArbitrationFee(
      transactionID, { value: arbitrationPrice }))
      .to.changeEtherBalances(
        [escrow, client],
        [arbitrationPrice, -arbitrationPrice]
      )
      .to.emit(escrow, 'HasToPayFee')
      .withArgs(transactionID, freelancer.address);

    await time.increase(constants.FEE_TIMEOUT);

    await expect(escrow.connect(client).timeOut(transactionID))
      .to.changeEtherBalances(
        [escrow, client, freelancer],
        [-arbitrationPrice, arbitrationPrice, 0]
      )
      .to.changeTokenBalances(
        usdt,
        [escrow, client, freelancer],
        [-amount, amount, 0]
      );
  });
});
