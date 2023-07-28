import { expect } from 'chai';
import { deployments } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

import { NerwoCentralizedArbitrator, NerwoEscrow, NerwoTetherToken } from '../../typechain-types';

import * as constants from '../../constants';
import { Actor, createDispute, getContracts } from '../utils';

describe('NerwoEscrow: rule (ERC20)', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  let actor = new Actor();
  let escrow: NerwoEscrow;
  let proxy: NerwoCentralizedArbitrator;
  let usdt: NerwoTetherToken;

  let platform: SignerWithAddress;
  let court: SignerWithAddress;
  let client: SignerWithAddress;
  let freelancer: SignerWithAddress;

  let amount: bigint, feeAmount: bigint;
  let arbitrationCost: bigint;
  let transactionID: bigint;
  let disputeID: bigint;

  beforeEach(async () => {
    ({ usdt } = await getContracts());
    ({
      escrow, proxy, platform, court, client, freelancer,
      transactionID, disputeID, amount
    } = await createDispute(actor, usdt));
    feeAmount = await escrow.calculateFeeRecipientAmount(amount);
    arbitrationCost = await escrow.getArbitrationCost();
  });

  it('testing errors', async () => {
    await expect(proxy.connect(platform).giveRuling(disputeID, 0))
      .to.be.reverted;

    await expect(proxy.connect(court).giveRuling(0, 0))
      .to.be.revertedWithCustomError(proxy, 'InvalidDispute');

    await expect(escrow.connect(client).pay(transactionID, amount))
      .to.revertedWithCustomError(escrow, 'InvalidStatus');
  });

  it('SENDER_WINS -> no platform fee', async () => {
    expect((await escrow.fetchRuling(transactionID)).isRuled).to.be.equal(false);
    await proxy.connect(court).giveRuling(disputeID, constants.Ruling.ClientWins);
    const { isRuled, ruling } = await escrow.fetchRuling(transactionID);
    expect(isRuled).to.be.equal(true);
    expect(ruling).to.be.equal(constants.Ruling.ClientWins);

    // SENDER_WINS -> no platform fee
    await expect(escrow.connect(client).acceptRuling(transactionID))
      .to.changeEtherBalances(
        [platform, client, freelancer],
        [0, arbitrationCost, 0]
      )
      .to.changeTokenBalances(
        usdt,
        [platform, client, freelancer],
        [0, amount, 0]
      );
  });

  it('RECEIVER_WINS -> platform gains', async () => {
    expect((await escrow.fetchRuling(transactionID)).isRuled).to.be.equal(false);
    await proxy.connect(court).giveRuling(disputeID, constants.Ruling.FreelancerWins);
    const { isRuled, ruling } = await escrow.fetchRuling(transactionID);
    expect(isRuled).to.be.equal(true);
    expect(ruling).to.be.equal(constants.Ruling.FreelancerWins);

    // RECEIVER_WINS -> platform gains
    await expect(escrow.connect(freelancer).acceptRuling(transactionID))
      .to.changeEtherBalances(
        [escrow, client, freelancer],
        [-arbitrationCost, 0, arbitrationCost]
      )
      .to.changeTokenBalances(
        usdt,
        [escrow, platform, client, freelancer],
        [-amount, feeAmount, 0, amount - feeAmount]
      );
  });

  it('Split amount', async () => {
    const splitAmount = amount / 2n;
    const splitArbitration = arbitrationCost / 2n;

    expect((await escrow.fetchRuling(transactionID)).isRuled).to.be.equal(false);
    await proxy.connect(court).giveRuling(disputeID, constants.Ruling.SplitAmount);
    const { isRuled, ruling } = await escrow.fetchRuling(transactionID);
    expect(isRuled).to.be.equal(true);
    expect(ruling).to.be.equal(constants.Ruling.SplitAmount);

    await expect(escrow.connect(client).acceptRuling(transactionID))
      .to.changeEtherBalances(
        [escrow, platform, client, freelancer],
        [-arbitrationCost, 0, splitArbitration, splitArbitration]
      )
      .to.changeTokenBalances(
        usdt,
        [escrow, platform, client, freelancer],
        [-amount, feeAmount, splitAmount, splitAmount - feeAmount]
      );
  });
});

describe('NerwoEscrow: rule (Native)', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  let actor = new Actor();
  let escrow: NerwoEscrow;
  let proxy: NerwoCentralizedArbitrator;

  let platform: SignerWithAddress;
  let court: SignerWithAddress;
  let client: SignerWithAddress;
  let freelancer: SignerWithAddress;

  let amount: bigint, feeAmount: bigint;
  let arbitrationCost: bigint;
  let transactionID: bigint;
  let disputeID: bigint;

  beforeEach(async () => {
    ({
      escrow, proxy, platform, court, client, freelancer,
      transactionID, disputeID, amount
    } = await createDispute(actor));
    feeAmount = await escrow.calculateFeeRecipientAmount(amount);
    arbitrationCost = await escrow.getArbitrationCost();
  });

  it('testing errors', async () => {
    await expect(proxy.connect(platform).giveRuling(disputeID, 0))
      .to.be.reverted;

    await expect(proxy.connect(court).giveRuling(0, 0))
      .to.be.revertedWithCustomError(proxy, 'InvalidDispute');

    await expect(escrow.connect(client).pay(transactionID, amount))
      .to.revertedWithCustomError(escrow, 'InvalidStatus');
  });

  it('SENDER_WINS -> no platform fee', async () => {
    expect((await escrow.fetchRuling(transactionID)).isRuled).to.be.equal(false);
    await proxy.connect(court).giveRuling(disputeID, constants.Ruling.ClientWins);
    const { isRuled, ruling } = await escrow.fetchRuling(transactionID);
    expect(isRuled).to.be.equal(true);
    expect(ruling).to.be.equal(constants.Ruling.ClientWins);

    // SENDER_WINS -> no platform fee
    await expect(escrow.connect(client).acceptRuling(transactionID))
      .to.changeEtherBalances(
        [platform, client, freelancer],
        [0, arbitrationCost + amount, 0]
      );
  });

  it('RECEIVER_WINS -> platform gains', async () => {
    expect((await escrow.fetchRuling(transactionID)).isRuled).to.be.equal(false);
    await proxy.connect(court).giveRuling(disputeID, constants.Ruling.FreelancerWins);
    const { isRuled, ruling } = await escrow.fetchRuling(transactionID);
    expect(isRuled).to.be.equal(true);
    expect(ruling).to.be.equal(constants.Ruling.FreelancerWins);

    // RECEIVER_WINS -> platform gains
    await expect(escrow.connect(freelancer).acceptRuling(transactionID))
      .to.changeEtherBalances(
        [escrow, client, freelancer],
        [-(arbitrationCost + amount), 0, arbitrationCost + amount - feeAmount]
      );
  });

  it('Split amount', async () => {
    const splitAmount = amount / 2n;
    const splitArbitration = arbitrationCost / 2n;

    expect((await escrow.fetchRuling(transactionID)).isRuled).to.be.equal(false);
    await proxy.connect(court).giveRuling(disputeID, constants.Ruling.SplitAmount);
    const { isRuled, ruling } = await escrow.fetchRuling(transactionID);
    expect(isRuled).to.be.equal(true);
    expect(ruling).to.be.equal(constants.Ruling.SplitAmount);

    await expect(escrow.connect(client).acceptRuling(transactionID))
      .to.changeEtherBalances(
        [escrow, platform, client, freelancer],
        [-arbitrationCost - amount, feeAmount, splitAmount + splitArbitration, splitAmount + splitArbitration - feeAmount]
      );
  });
});
