import { expect } from 'chai';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { deployments, ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { NerwoEscrowV1, Rogue } from '../typechain-types';

import * as constants from '../constants';

describe('NerwoEscrow: pay', function () {
  let escrow: NerwoEscrowV1;
  let platform: SignerWithAddress;
  let sender: SignerWithAddress;
  let rogue: Rogue;

  this.beforeEach(async () => {
    [, platform, , sender,] = await ethers.getSigners();

    await deployments.fixture(['NerwoCentralizedArbitratorV1', 'NerwoEscrowV1']);

    let deployment = await deployments.get('NerwoEscrowV1');
    escrow = await ethers.getContractAt('NerwoEscrowV1', deployment.address);

    const Rogue = await ethers.getContractFactory("Rogue");
    rogue = await Rogue.deploy(escrow.address);
    await rogue.deployed();
  });

  it('rogue as recipient', async () => {
    const minimalAmount = await escrow.minimalAmount();
    let amount = ethers.utils.parseEther('0.02')

    // fund rogue contract
    const rogueFunds = ethers.utils.parseEther('10.0');
    await expect(sender.sendTransaction({ to: rogue.address, value: rogueFunds }))
      .to.changeEtherBalance(rogue, rogueFunds);

    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT, rogue.address, '', { value: minimalAmount.sub(1) }))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(minimalAmount);

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

    await expect(escrow.connect(sender).pay(_transactionID, 0))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    await expect(escrow.connect(sender).pay(_transactionID, amount.mul(2)))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    amount = amount.div(2);
    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);

    await rogue.setAmount(amount);
    await rogue.setAction(constants.RogueAction.Pay);

    // FIXME: emit order in sol
    // FIXME: make SendFailed and Payment mutually exclusive?
    await expect(escrow.connect(sender).pay(_transactionID, amount))
      .to.changeEtherBalances(
        [escrow, platform, rogue],
        [feeAmount.mul(-1), feeAmount, 0]
      )
      .to.emit(escrow, 'SendFailed').withArgs(rogue.address, amount.sub(feeAmount), anyValue)
      .to.emit(escrow, 'Payment').withArgs(_transactionID, amount, sender.address)
      .to.emit(escrow, 'FeeRecipientPayment');

    await expect(escrow.connect(sender).pay(_transactionID, amount.mul(2)))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    await expect(escrow.connect(sender).pay(_transactionID, amount))
      .to.changeEtherBalances(
        [escrow, platform, rogue],
        [feeAmount.mul(-1), feeAmount, 0]
      )
      .to.emit(escrow, 'Payment').withArgs(_transactionID, amount, sender.address)
      .to.emit(escrow, 'FeeRecipientPayment');
  });
});
