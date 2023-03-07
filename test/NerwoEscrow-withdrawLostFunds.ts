import { expect } from 'chai';
import { ethers } from 'hardhat';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';

import * as constants from '../constants';
import { deployFixture } from './fixtures';

describe('NerwoEscrow: withdrawLostFunds', function () {

  async function createTransaction() {
    const { arbitrator, escrow, rogue, deployer, platform, sender, receiver }
      = await loadFixture(deployFixture);

    const amount = ethers.utils.parseEther('0.02');
    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);

    const blockNumber = await ethers.provider.getBlockNumber();

    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT, rogue.address, '', { value: amount }))
      .to.changeEtherBalances(
        [platform, sender],
        [0, amount.mul(-1)]
      )
      .to.emit(escrow, 'TransactionCreated');

    const events = await escrow.queryFilter(escrow.filters.TransactionCreated(), blockNumber);
    expect(events).to.be.an('array').that.lengthOf(1);
    expect(events[0].args!).is.not.undefined;

    const { _transactionID } = events[0].args!;
    return {
      arbitrator, escrow, rogue,
      deployer, platform, sender, receiver,
      amount, feeAmount, _transactionID
    };
  }

  it('Ownable', async () => {
    const { escrow, sender } = await loadFixture(deployFixture);

    await expect(escrow.connect(sender).withdrawLostFunds())
      .to.be.revertedWith('Ownable: caller is not the owner');
  });

  it('NoLostFunds', async () => {
    const { escrow, deployer } = await loadFixture(createTransaction);

    await expect(escrow.connect(deployer).withdrawLostFunds())
      .to.be.revertedWithCustomError(escrow, 'NoLostFunds');
  });

  it('FundsRecovered', async () => {
    const { escrow, rogue, deployer, platform, sender, amount, feeAmount, _transactionID }
      = await loadFixture(createTransaction);

    await rogue.setAction(constants.RogueAction.Revert);

    await expect(escrow.connect(sender).pay(_transactionID, amount))
      .to.changeEtherBalances(
        [escrow, platform, rogue],
        [feeAmount.mul(-1), feeAmount, 0]
      )
      .to.emit(escrow, 'SendFailed').withArgs(rogue.address, amount.sub(feeAmount), anyValue);

    const lostFunds = await escrow.lostFunds();

    await expect(escrow.connect(deployer).withdrawLostFunds())
      .to.changeEtherBalances(
        [escrow, deployer],
        [lostFunds.mul(-1), lostFunds]
      )
      .to.emit(escrow, 'FundsRecovered').withArgs(deployer.address, lostFunds);

    expect(await escrow.lostFunds()).to.be.equal(0);
  });
});
