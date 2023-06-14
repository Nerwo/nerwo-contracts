import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';

import * as constants from '../../constants';
import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: rule', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  let amount: bigint, feeAmount: bigint;
  let arbitrationPrice: bigint;
  let transactionID: bigint;
  let disputeID: bigint;
  let fliplop = true;

  beforeEach(async () => {
    const { escrow, proxy, usdt } = await getContracts();
    const { sender, receiver } = await getSigners();
    amount = await randomAmount();
    feeAmount = await escrow.calculateFeeRecipientAmount(amount);
    arbitrationPrice = await escrow.arbitrationCost();

    transactionID = await createTransaction(sender, receiver.address, usdt, amount);

    const payBySender = () => escrow.connect(sender)
      .payArbitrationFeeBySender(transactionID, { value: arbitrationPrice });

    const payByReceiver = () => escrow.connect(receiver)
      .payArbitrationFeeByReceiver(transactionID, { value: arbitrationPrice });

    fliplop = !fliplop;
    await expect(fliplop ? payBySender() : payByReceiver())
      .to.emit(escrow, 'HasToPayFee');

    const blockNumber = await ethers.provider.getBlockNumber();

    await expect(fliplop ? payByReceiver() : payBySender())
      .to.emit(proxy, 'Dispute')
      .to.not.emit(escrow, 'HasToPayFee');

    const events = await proxy.queryFilter(proxy.filters.Dispute(), blockNumber);
    expect(events).to.be.an('array');
    expect(events.at(-1)?.args?._disputeID).is.not.undefined;
    disputeID = events.at(-1)!.args!._disputeID!;
  });

  it('testing errors', async () => {
    const { proxy, escrow } = await getContracts();
    const { platform, court, sender } = await getSigners();

    await expect(proxy.connect(platform).giveRuling(disputeID, 0))
      .to.be.revertedWith('Ownable: caller is not the owner');

    await expect(proxy.connect(court).giveRuling(0, 0))
      .to.be.revertedWithCustomError(proxy, 'InvalidDispute');

    const transactionID = await escrow.lastTransaction();
    await expect(escrow.connect(sender).pay(transactionID, amount))
      .to.revertedWithCustomError(escrow, 'InvalidStatus');
  });

  it('SENDER_WINS -> no platform fee', async () => {
    const { proxy, escrow, usdt } = await getContracts();
    const { platform, court, sender, receiver } = await getSigners();

    expect((await escrow.fetchRuling(transactionID)).isRuled).to.be.equal(false);
    await proxy.connect(court).giveRuling(disputeID, constants.SENDER_WINS);
    const {isRuled, ruling} = await escrow.fetchRuling(transactionID);
    expect (isRuled).to.be.equal(true);
    expect (ruling).to.be.equal(constants.SENDER_WINS);

    // SENDER_WINS -> no platform fee
    await expect(escrow.connect(sender).acceptRuling(transactionID))
      .to.changeEtherBalances(
        [platform, sender, receiver],
        [0, arbitrationPrice, 0]
      )
      .to.changeTokenBalances(
        usdt,
        [platform, sender, receiver],
        [0, amount, 0]
      );
  });

  it('RECEIVER_WINS -> platform gains', async () => {
    const { proxy, escrow, usdt } = await getContracts();
    const { platform, court, sender, receiver } = await getSigners();

    expect((await escrow.fetchRuling(transactionID)).isRuled).to.be.equal(false);
    await proxy.connect(court).giveRuling(disputeID, constants.RECEIVER_WINS);
    const {isRuled, ruling} = await escrow.fetchRuling(transactionID);
    expect (isRuled).to.be.equal(true);
    expect (ruling).to.be.equal(constants.RECEIVER_WINS);

    // RECEIVER_WINS -> platform gains
    await expect(escrow.connect(receiver).acceptRuling(transactionID))
      .to.changeEtherBalances(
        [escrow, sender, receiver],
        [-arbitrationPrice, 0, arbitrationPrice]
      )
      .to.changeTokenBalances(
        usdt,
        [escrow, platform, sender, receiver],
        [-amount, feeAmount, 0, amount - feeAmount]
      );
  });

  it('Split amount', async () => {
    const { proxy, escrow, usdt } = await getContracts();
    const { platform, court, sender, receiver } = await getSigners();

    const splitAmount = amount / 2n;
    const splitFee = feeAmount / 2n;

    expect((await escrow.fetchRuling(transactionID)).isRuled).to.be.equal(false);
    await proxy.connect(court).giveRuling(disputeID, constants.SPLIT_AMOUNT);
    const {isRuled, ruling} = await escrow.fetchRuling(transactionID);
    expect (isRuled).to.be.equal(true);
    expect (ruling).to.be.equal(constants.SPLIT_AMOUNT);

    await expect(escrow.connect(sender).acceptRuling(transactionID))
      .to.changeEtherBalances(
        [escrow, sender, receiver],
        [-arbitrationPrice, 0, arbitrationPrice]
      )
      .to.changeTokenBalances(
        usdt,
        [escrow, platform, sender, receiver],
        [-amount, splitFee, splitAmount, splitAmount - splitFee]
      );
  });
});
