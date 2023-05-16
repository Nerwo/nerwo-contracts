import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';

import * as constants from '../../constants';
import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: misc', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'TetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('Creating transaction, then pay', async () => {
    const { escrow, usdt } = await getContracts();
    const { platform, sender, receiver } = await getSigners();

    const amount = await randomAmount();
    const platformFee = await escrow.calculateFeeRecipientAmount(amount);

    const transactionID = await createTransaction(sender, receiver.address, usdt, amount);

    await expect(escrow.connect(sender).pay(transactionID, amount))
      .to.changeTokenBalances(
        usdt,
        [platform, receiver],
        [platformFee, amount.sub(platformFee)]
      )
      .to.not.emit(escrow, 'SendFailed');
  });

  it('Creating transaction with arbitrage', async () => {
    const { arbitrator, escrow, usdt } = await getContracts();
    const { platform, court, sender, receiver } = await getSigners();

    let amount = await randomAmount();
    const arbitrationPrice = await arbitrator.arbitrationCost([]);

    let transactionID = await createTransaction(sender, receiver.address, usdt, amount);

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
        [0, arbitrationPrice, 0]
      )
      .to.changeTokenBalances(
        usdt,
        [platform, sender, receiver],
        [0, amount, 0]
      )
      .to.emit(escrow, 'Ruling');

    // new Transaction
    amount = await randomAmount();

    transactionID = await createTransaction(sender, receiver.address, usdt, amount);

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
        [escrow, sender, receiver],
        [arbitrationPrice.mul(-1), 0, arbitrationPrice]
      )
      .to.changeTokenBalances(
        usdt,
        [escrow, platform, sender, receiver],
        [amount.mul(-1), feeAmount, 0, amount.sub(feeAmount)]
      )
      .to.emit(escrow, 'Ruling');
  });
});
