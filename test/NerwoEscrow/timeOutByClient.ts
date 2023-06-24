import { time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { deployments } from 'hardhat';

import * as constants from '../../constants';
import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: timeOutByClient', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('NoTimeout', async () => {
    const { escrow, usdt } = await getContracts();
    const { client, freelance } = await getSigners();
    const freelanceAddress = await freelance.getAddress();

    const amount = await randomAmount();
    const arbitrationPrice = await escrow.getArbitrationCost();
    const transactionID = await createTransaction(client, freelanceAddress, usdt, amount);

    await expect(escrow.connect(client).payArbitrationFee(
      transactionID, { value: arbitrationPrice }))
      .to.emit(escrow, 'HasToPayFee')
      .withArgs(transactionID, freelanceAddress);

    await expect(escrow.connect(client).timeOut(transactionID))
      .to.be.revertedWithCustomError(escrow, 'NoTimeout');
  });

  it('InvalidStatus', async () => {
    const { escrow, usdt } = await getContracts();
    const { client, freelance } = await getSigners();

    const amount = await randomAmount();
    const transactionID = await createTransaction(client, await freelance.getAddress(), usdt, amount);

    await time.increase(constants.FEE_TIMEOUT);

    await expect(escrow.connect(client).timeOut(transactionID))
      .to.be.revertedWithCustomError(escrow, 'InvalidStatus');
  });

  it('Timeout', async () => {
    const { escrow, usdt } = await getContracts();
    const { client, freelance } = await getSigners();
    const freelanceAddress = await freelance.getAddress();

    const amount = await randomAmount();
    const arbitrationPrice = await escrow.getArbitrationCost();
    const transactionID = await createTransaction(client, freelanceAddress, usdt, amount);

    await expect(escrow.connect(client).payArbitrationFee(
      transactionID, { value: arbitrationPrice }))
      .to.changeEtherBalances(
        [escrow, client],
        [arbitrationPrice, -arbitrationPrice]
      )
      .to.emit(escrow, 'HasToPayFee')
      .withArgs(transactionID, freelanceAddress);

    await time.increase(constants.FEE_TIMEOUT);

    await expect(escrow.connect(client).timeOut(transactionID))
      .to.changeEtherBalances(
        [escrow, client, freelance],
        [-arbitrationPrice, arbitrationPrice, 0]
      )
      .to.changeTokenBalances(
        usdt,
        [escrow, client, freelance],
        [-amount, amount, 0]
      );
  });
});
