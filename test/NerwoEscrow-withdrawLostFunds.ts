import { expect } from 'chai';
import { deployments } from 'hardhat';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';

import * as constants from '../constants';
import { getContracts, getSigners, createTransaction, randomAmount } from './utils';

describe('NerwoEscrow: withdrawLostFunds', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'Rogue'], {
      keepExistingDeployments: true
    });
  });

  it('Ownable', async () => {
    const { escrow } = await getContracts();
    const { sender } = await getSigners();

    await expect(escrow.connect(sender).withdrawLostFunds())
      .to.be.revertedWith('Ownable: caller is not the owner');
  });

  it('NoLostFunds', async () => {
    const { escrow } = await getContracts();
    const { deployer } = await getSigners();

    await expect(escrow.connect(deployer).withdrawLostFunds())
      .to.be.revertedWithCustomError(escrow, 'NoLostFunds');
  });

  it('FundsRecovered', async () => {
    const { escrow, rogue } = await getContracts();
    const { deployer, platform, sender } = await getSigners();

    const amount = await randomAmount();
    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);
    const transactionID = await createTransaction(sender, rogue.address, amount);

    await rogue.setAction(constants.RogueAction.Revert);
    expect(await escrow.connect(sender).pay(transactionID, amount))
      .to.changeEtherBalances(
        [escrow, platform, rogue],
        [feeAmount.mul(-1), feeAmount, 0]
      )
      .to.emit(escrow, 'SendFailed').withArgs(rogue.address, amount.sub(feeAmount), anyValue);
    await rogue.setAction(constants.RogueAction.None);

    const lostFunds = await escrow.lostFunds();

    expect(await escrow.connect(deployer).withdrawLostFunds())
      .to.changeEtherBalances(
        [escrow, deployer],
        [lostFunds.mul(-1), lostFunds]
      )
      .to.emit(escrow, 'FundsRecovered').withArgs(deployer.address, lostFunds);

    expect(await escrow.lostFunds()).to.be.equal(0);
  });
});
