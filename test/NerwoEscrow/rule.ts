import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';

import * as constants from '../../constants';
import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';
import { BigNumber } from 'ethers';

describe('NerwoEscrow: rule', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'TetherToken'], {
      keepExistingDeployments: true
    });
  });

  let amount: BigNumber, feeAmount: BigNumber;
  let arbitrationPrice: BigNumber;
  let disputeID: BigNumber;

  beforeEach(async () => {
    const { arbitrator, escrow, usdt } = await getContracts();
    const { sender, receiver } = await getSigners();
    amount = await randomAmount();
    feeAmount = await escrow.calculateFeeRecipientAmount(amount);
    arbitrationPrice = await arbitrator.arbitrationCost([]);

    const transactionID = await createTransaction(sender, receiver.address, usdt, amount);

    await expect(escrow.connect(receiver).payArbitrationFeeByReceiver(
      transactionID, { value: arbitrationPrice }))
      .to.emit(escrow, 'HasToPayFee');

    const blockNumber = await ethers.provider.getBlockNumber();
    await expect(escrow.connect(sender).payArbitrationFeeBySender(
      transactionID, { value: arbitrationPrice }))
      .to.emit(escrow, 'Dispute')
      .to.not.emit(escrow, 'HasToPayFee');

    const events = await escrow.queryFilter(escrow.filters.Dispute(), blockNumber);
    expect(events).to.be.an('array');
    expect(events.at(-1)?.args?._disputeID).is.not.undefined;
    disputeID = events.at(-1)!.args!._disputeID!;

    await expect(escrow.connect(sender).pay(transactionID, amount))
      .to.revertedWithCustomError(escrow, 'InvalidStatus');

  });

  it('testing errors', async () => {
    const { arbitrator, escrow, usdt } = await getContracts();
    const { platform, court, sender, receiver } = await getSigners();

    await expect(arbitrator.connect(platform).giveRuling(disputeID, 0))
      .to.be.revertedWith('Ownable: caller is not the owner');

    await expect(arbitrator.connect(court).giveRuling(0, 0))
      .to.be.revertedWithCustomError(arbitrator, 'InvalidDispute');
  });

  it('SENDER_WINS -> no platform fee', async () => {
    const { arbitrator, escrow, usdt } = await getContracts();
    const { platform, court, sender, receiver } = await getSigners();

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
  });

  it('RECEIVER_WINS -> platform gains', async () => {
    const { arbitrator, escrow, usdt } = await getContracts();
    const { platform, court, sender, receiver } = await getSigners();

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

  it('Split amount', async () => {
    const { arbitrator, escrow, usdt } = await getContracts();
    const { platform, court, sender, receiver } = await getSigners();

    await expect(arbitrator.connect(court).giveRuling(disputeID, 0))
      .to.changeEtherBalances(
        [escrow, sender, receiver],
        [arbitrationPrice.mul(-1), 0, arbitrationPrice]
      )
      .to.changeTokenBalances(
        usdt,
        [escrow, platform, sender, receiver],
        [amount.mul(-1), feeAmount, amount.div(2), amount.div(2).sub(feeAmount)]
      )
      .to.emit(escrow, 'Ruling');
  });
});
