import { time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { deployments } from 'hardhat';

import * as constants from '../../constants';
import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: timeOutByFreelance', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('NoTimeout', async () => {
    const { escrow, usdt } = await getContracts();
    const { client, freelance } = await getSigners();

    const amount = await randomAmount();
    const arbitrationPrice = await escrow.getArbitrationCost();
    const transactionID = await createTransaction(client, await freelance.getAddress(), usdt, amount);

    await expect(escrow.connect(freelance).payArbitrationFee(
      transactionID, { value: arbitrationPrice }))
      .to.emit(escrow, 'HasToPayFee')
      .withArgs(transactionID, await client.getAddress());

    await expect(escrow.connect(freelance).timeOut(transactionID))
      .to.be.revertedWithCustomError(escrow, 'NoTimeout');
  });

  it('InvalidStatus', async () => {
    const { escrow, usdt } = await getContracts();
    const { client, freelance } = await getSigners();

    const amount = await randomAmount();
    const transactionID = await createTransaction(client, await freelance.getAddress(), usdt, amount);

    await time.increase(constants.FEE_TIMEOUT);

    await expect(escrow.connect(freelance).timeOut(transactionID))
      .to.be.revertedWithCustomError(escrow, 'InvalidStatus');
  });

  it('Timeout', async () => {
    const { escrow, usdt } = await getContracts();
    const { platform, client, freelance } = await getSigners();
    const freelanceAddress = await freelance.getAddress();

    const amount = await randomAmount();
    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);
    const arbitrationPrice = await escrow.getArbitrationCost();
    const transactionID = await createTransaction(client, freelanceAddress, usdt, amount);

    await expect(escrow.connect(freelance).payArbitrationFee(
      transactionID, { value: arbitrationPrice }))
      .to.changeEtherBalances(
        [escrow, client, freelance],
        [arbitrationPrice, 0, -arbitrationPrice]
      )
      .to.emit(escrow, 'HasToPayFee')
      .withArgs(transactionID, await client.getAddress());

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
