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
    const { client, freelance } = await getSigners();

    const clientAddress = await client.getAddress();
    const freelanceAddress = await freelance.getAddress();

    amount = await randomAmount();
    feeAmount = await escrow.calculateFeeRecipientAmount(amount);
    arbitrationPrice = await escrow.getArbitrationCost();

    transactionID = await createTransaction(client, freelanceAddress, usdt, amount);

    const payByClient = () => escrow.connect(client)
      .payArbitrationFee(transactionID, { value: arbitrationPrice });

    const payByFreelance = () => escrow.connect(freelance)
      .payArbitrationFee(transactionID, { value: arbitrationPrice });

    fliplop = !fliplop;
    await expect(fliplop ? payByClient() : payByFreelance())
      .to.emit(escrow, 'HasToPayFee')
      .withArgs(transactionID, fliplop ? freelanceAddress : clientAddress);

    const blockNumber = await ethers.provider.getBlockNumber();

    await expect(fliplop ? payByFreelance() : payByClient())
      .to.emit(proxy, 'Dispute')
      .to.not.emit(escrow, 'HasToPayFee');

    const events = await proxy.queryFilter(proxy.filters.Dispute(), blockNumber);
    expect(events).to.be.an('array');
    expect(events.at(-1)?.args?._disputeID).is.not.undefined;
    disputeID = events.at(-1)!.args!._disputeID!;
  });

  it('testing errors', async () => {
    const { proxy, escrow } = await getContracts();
    const { platform, court, client } = await getSigners();

    await expect(proxy.connect(platform).giveRuling(disputeID, 0))
      .to.be.revertedWith('Ownable: caller is not the owner');

    await expect(proxy.connect(court).giveRuling(0, 0))
      .to.be.revertedWithCustomError(proxy, 'InvalidDispute');

    const transactionID = await escrow.lastTransaction();
    await expect(escrow.connect(client).pay(transactionID, amount))
      .to.revertedWithCustomError(escrow, 'InvalidStatus');
  });

  it('SENDER_WINS -> no platform fee', async () => {
    const { proxy, escrow, usdt } = await getContracts();
    const { platform, court, client, freelance } = await getSigners();

    expect((await escrow.fetchRuling(transactionID)).isRuled).to.be.equal(false);
    await proxy.connect(court).giveRuling(disputeID, constants.Ruling.ClientWins);
    const { isRuled, ruling } = await escrow.fetchRuling(transactionID);
    expect(isRuled).to.be.equal(true);
    expect(ruling).to.be.equal(constants.Ruling.ClientWins);

    // SENDER_WINS -> no platform fee
    await expect(escrow.connect(client).acceptRuling(transactionID))
      .to.changeEtherBalances(
        [platform, client, freelance],
        [0, arbitrationPrice, 0]
      )
      .to.changeTokenBalances(
        usdt,
        [platform, client, freelance],
        [0, amount, 0]
      );
  });

  it('RECEIVER_WINS -> platform gains', async () => {
    const { proxy, escrow, usdt } = await getContracts();
    const { platform, court, client, freelance } = await getSigners();

    expect((await escrow.fetchRuling(transactionID)).isRuled).to.be.equal(false);
    await proxy.connect(court).giveRuling(disputeID, constants.Ruling.FreelanceWins);
    const { isRuled, ruling } = await escrow.fetchRuling(transactionID);
    expect(isRuled).to.be.equal(true);
    expect(ruling).to.be.equal(constants.Ruling.FreelanceWins);

    // RECEIVER_WINS -> platform gains
    await expect(escrow.connect(freelance).acceptRuling(transactionID))
      .to.changeEtherBalances(
        [escrow, client, freelance],
        [-arbitrationPrice, 0, arbitrationPrice]
      )
      .to.changeTokenBalances(
        usdt,
        [escrow, platform, client, freelance],
        [-amount, feeAmount, 0, amount - feeAmount]
      );
  });

  it('Split amount', async () => {
    const { proxy, escrow, usdt } = await getContracts();
    const { platform, court, client, freelance } = await getSigners();

    const splitAmount = amount / 2n;
    const splitFee = feeAmount / 2n;

    expect((await escrow.fetchRuling(transactionID)).isRuled).to.be.equal(false);
    await proxy.connect(court).giveRuling(disputeID, constants.Ruling.SplitAmount);
    const { isRuled, ruling } = await escrow.fetchRuling(transactionID);
    expect(isRuled).to.be.equal(true);
    expect(ruling).to.be.equal(constants.Ruling.SplitAmount);

    await expect(escrow.connect(client).acceptRuling(transactionID))
      .to.changeEtherBalances(
        [escrow, client, freelance],
        [-arbitrationPrice, 0, arbitrationPrice]
      )
      .to.changeTokenBalances(
        usdt,
        [escrow, platform, client, freelance],
        [-amount, splitFee, splitAmount, splitAmount - splitFee]
      );
  });
});
