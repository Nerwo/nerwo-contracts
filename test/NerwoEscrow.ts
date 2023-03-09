import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';

import * as constants from '../constants';
import { getContracts, getSigners, fund, createTransaction, randomAmount } from './utils';

describe('NerwoEscrow: misc', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'Rogue'], {
      keepExistingDeployments: true
    });
  });

  it('Creating transaction, then pay', async () => {
    const { escrow } = await getContracts();
    const { platform, sender, receiver } = await getSigners();

    const amount = ethers.utils.parseEther('0.01');
    const platformFee = await escrow.calculateFeeRecipientAmount(amount);

    const transactionID = await createTransaction(sender, receiver.address, amount);

    await expect(escrow.connect(sender).pay(transactionID, amount))
      .to.changeEtherBalances(
        [platform, receiver],
        [platformFee, amount.sub(platformFee)]
      )
      .to.not.emit(escrow, 'SendFailed');
  });

  it('Creating transaction with rogue, then pay', async () => {
    const { escrow, rogue } = await getContracts();
    const { platform, sender } = await getSigners();

    const amount = ethers.utils.parseEther('0.02');
    const payAmount = amount.div(2);
    const platformFee = await escrow.calculateFeeRecipientAmount(payAmount);

    const transactionID = await createTransaction(sender, rogue.address, amount);

    await rogue.setTransaction(transactionID);
    await rogue.setAmount(payAmount);

    await rogue.setAction(constants.RogueAction.Pay);
    await expect(escrow.connect(sender).pay(transactionID, payAmount))
      .to.changeEtherBalances(
        [platform, rogue],
        [platformFee, 0]
      )
      .to.emit(escrow, 'SendFailed');
    await rogue.setAction(constants.RogueAction.None);

    await expect(escrow.connect(sender).pay(transactionID, payAmount))
      .to.changeEtherBalances(
        [platform, rogue],
        [platformFee, payAmount.sub(platformFee)]
      )
      .to.not.emit(escrow, 'SendFailed');
  });

  it('Creating transaction with arbitrage', async () => {
    const { arbitrator, escrow } = await getContracts();
    const { platform, court, sender, receiver } = await getSigners();

    let amount = ethers.utils.parseEther('0.04');
    const arbitrationPrice = await arbitrator.arbitrationCost([]);

    let transactionID = await createTransaction(sender, receiver.address, amount);

    await expect(escrow.connect(receiver).payArbitrationFeeByReceiver(
      transactionID, { value: arbitrationPrice }))
      .to.emit(escrow, 'HasToPayFee');

    let blockNumber = await ethers.provider.getBlockNumber();
    await expect(escrow.connect(sender).payArbitrationFeeBySender(
      transactionID, { value: arbitrationPrice }))
      .to.emit(escrow, 'Dispute')
      .to.not.emit(escrow, 'HasToPayFee');

    let events = await escrow.queryFilter(escrow.filters.Dispute(), blockNumber);
    expect(events).to.be.an('array');
    expect(events.at(-1)?.args?._disputeID).is.not.undefined;
    let disputeID = events.at(-1)!.args!._disputeID!;

    await expect(escrow.connect(sender).pay(transactionID, amount))
      .to.revertedWithCustomError(escrow, 'InvalidStatus');

    await expect(arbitrator.connect(sender).giveRuling(disputeID, constants.SENDER_WINS)).to.be.rejectedWith(
      'Ownable: caller is not the owner');

    // SENDER_WINS -> no platform fee
    await expect(arbitrator.connect(court).giveRuling(disputeID, constants.SENDER_WINS))
      .to.changeEtherBalances(
        [platform, sender, receiver],
        [0, arbitrationPrice.add(amount), 0]
      )
      .to.emit(escrow, 'Ruling');

    // new Transaction
    amount = ethers.utils.parseEther('0.08');

    transactionID = await createTransaction(sender, receiver.address, amount);

    await expect(escrow.connect(receiver).payArbitrationFeeByReceiver(
      transactionID, { value: arbitrationPrice }))
      .to.changeEtherBalances(
        [escrow, receiver],
        [arbitrationPrice, arbitrationPrice.mul(-1)]
      )
      .to.emit(escrow, 'HasToPayFee')
      .to.not.emit(escrow, 'Dispute');

    blockNumber = await ethers.provider.getBlockNumber();
    await expect(escrow.connect(sender).payArbitrationFeeBySender(
      transactionID, { value: arbitrationPrice }))
      .to.emit(escrow, 'Dispute')
      .to.not.emit(escrow, 'HasToPayFee');

    events = await escrow.queryFilter(escrow.filters.Dispute(), blockNumber);
    expect(events).to.be.an('array');
    expect(events.at(-1)?.args?._disputeID).is.not.undefined;
    disputeID = events.at(-1)!.args!._disputeID!;

    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);
    // RECEIVER_WINS -> platform gains
    await expect(arbitrator.connect(court).giveRuling(disputeID, constants.RECEIVER_WINS))
      .to.changeEtherBalances(
        [platform, sender, receiver],
        [feeAmount, 0, arbitrationPrice.add(amount).sub(feeAmount)]
      )
      .to.emit(escrow, 'Ruling');
  });

  it('Creating arbitrage transaction with rogue', async () => {
    const { arbitrator, escrow, rogue } = await getContracts();
    const { platform, court, receiver } = await getSigners();

    await fund(rogue, ethers.utils.parseEther('10.0'));

    const arbitrationPrice = await arbitrator.arbitrationCost([]);

    const amount = await randomAmount();
    await rogue.setAmount(amount);

    let blockNumber = await ethers.provider.getBlockNumber();
    await expect(rogue.createTransaction(
      constants.TIMEOUT_PAYMENT, receiver.address, ''))
      .to.changeEtherBalances(
        [platform, rogue],
        [0, amount.mul(-1)]
      )
      .to.emit(escrow, 'TransactionCreated');

    const events = await escrow.queryFilter(escrow.filters.TransactionCreated(), blockNumber);
    expect(events).to.be.an('array');
    expect(events.at(-1)?.args?._transactionID).is.not.undefined;

    const _transactionID = events.at(-1)!.args!._transactionID!;

    await expect(escrow.connect(receiver).payArbitrationFeeByReceiver(_transactionID, {
      value: arbitrationPrice.mul(2)
    })).to.be.revertedWithCustomError(escrow, 'InvalidAmount');

    await expect(escrow.connect(receiver).payArbitrationFeeByReceiver(
      _transactionID, { value: arbitrationPrice }))
      .to.changeEtherBalances(
        [escrow, receiver],
        [arbitrationPrice, arbitrationPrice.mul(-1)]
      )
      .to.emit(escrow, 'HasToPayFee')
      .to.not.emit(escrow, 'Dispute');

    await rogue.setAmount(arbitrationPrice);

    blockNumber = await ethers.provider.getBlockNumber();
    await expect(rogue.payArbitrationFeeBySender(_transactionID))
      .to.changeEtherBalance(rogue, arbitrationPrice.mul(-1))
      .to.emit(escrow, 'Dispute')
      .to.not.emit(escrow, 'HasToPayFee');

    const dEvents = await escrow.queryFilter(escrow.filters.Dispute(), blockNumber);
    expect(dEvents).to.be.an('array');
    expect(dEvents.at(-1)?.args?._disputeID).is.not.undefined;
    const disputeID = dEvents.at(-1)!.args!._disputeID!;

    await rogue.setAction(constants.RogueAction.Revert);
    await expect(arbitrator.connect(court).giveRuling(disputeID, constants.SENDER_WINS))
      .to.changeEtherBalances(
        [platform, rogue, receiver],
        [0, 0, 0])
      .to.emit(escrow, 'SendFailed');
    await rogue.setAction(constants.RogueAction.None);
  });
});
