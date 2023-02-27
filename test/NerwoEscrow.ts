import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { BigNumber } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BaseContract } from '@ethersproject/contracts';

import { NerwoCentralizedArbitratorV1, NerwoEscrowV1, Rogue } from '../typechain-types';

import * as constants from './constants';
import * as utils from './utils';

describe('NerwoEscrow', function () {
  const arbitrationPrice = ethers.utils.parseEther('0.0001');
  let escrow: NerwoEscrowV1;
  let arbitrator: NerwoCentralizedArbitratorV1;
  let platform: SignerWithAddress, court: SignerWithAddress;
  let sender: SignerWithAddress, receiver: SignerWithAddress;
  let rogue: Rogue;

  this.beforeEach(async () => {
    const NerwoCentralizedArbitratorV1 = await ethers.getContractFactory("NerwoCentralizedArbitratorV1");
    arbitrator = await upgrades.deployProxy(NerwoCentralizedArbitratorV1, [constants.ARBITRATOR_PRICE], {
      kind: 'uups',
      initializer: 'initialize',
    }) as NerwoCentralizedArbitratorV1;
    await arbitrator.deployed();

    const ARGS = [
      constants.ZERO_ADDRESS,
      [], // _arbitratorExtraData
      constants.ZERO_ADDRESS,
      0,
      0
    ];

    const NerwoEscrowV1 = await ethers.getContractFactory("NerwoEscrowV1");
    escrow = await upgrades.deployProxy(NerwoEscrowV1, ARGS, {
      kind: 'uups',
      initializer: 'initialize',
    }) as NerwoEscrowV1;
    await escrow.deployed();

    const Rogue = await ethers.getContractFactory("Rogue");
    rogue = await Rogue.deploy();
    await rogue.deployed();

    [, platform, court, sender, receiver] = await ethers.getSigners();

    await escrow.transferOwnership(platform.address);
    await escrow.connect(platform).setArbitrator(
      arbitrator.address,
      [],
      platform.address,
      constants.FEE_RECIPIENT_BASISPOINT,
      constants.FEE_TIMEOUT);
  });

  async function createTransaction(
    _sender: SignerWithAddress,
    _receiver: SignerWithAddress | BaseContract,
    amount: BigNumber): Promise<BigNumber> {
    const txResponse = await escrow.connect(_sender).createTransaction(
      constants.TIMEOUT_PAYMENT,
      _receiver.address,
      'evidence',
      { value: amount });

    const event = await utils.findEventByName(txResponse, 'TransactionCreated');
    expect(event.args).to.not.be.empty;
    const { _transactionID } = event.args!;
    return _transactionID;
  }

  it('Creating transaction, then pay', async () => {
    const platformBalance = await platform.getBalance();
    const receiverBalance = await receiver.getBalance();

    const amount = ethers.utils.parseEther('0.001');
    const _transactionID = await createTransaction(sender, receiver, amount);

    await escrow.connect(sender).pay(_transactionID, amount);

    const platformGain = (await platform.getBalance()).sub(platformBalance);
    const expectedFee = amount.mul(constants.FEE_RECIPIENT_BASISPOINT).div(10000);
    expect(platformGain).to.be.equal(expectedFee);

    const receiverGain = (await receiver.getBalance()).sub(receiverBalance);
    expect(receiverGain).to.be.equal(amount.sub(expectedFee));
  });

  it('Creating transaction with rogue, then pay', async () => {
    const platformBalance = await platform.getBalance();
    const rogueBalance = await rogue.getBalance();

    const amount = ethers.utils.parseEther('0.001');
    const _transactionID = await createTransaction(sender, rogue, amount);

    rogue.setAction(constants.ACTION_PAY);
    rogue.setTransaction(_transactionID, amount.div(2));
    await escrow.connect(sender).pay(_transactionID, amount.div(2));

    const platformGain = (await platform.getBalance()).sub(platformBalance);
    const expectedFee = amount.div(2).mul(constants.FEE_RECIPIENT_BASISPOINT).div(10000);
    expect(platformGain).to.be.equal(expectedFee);

    const rogueGain = (await rogue.getBalance()).sub(rogueBalance);
    expect(rogueGain).to.be.equal(BigNumber.from(0));
  });

  async function createDispute(
    _transactionID: BigNumber,
    _sender: SignerWithAddress,
    _receiver: SignerWithAddress,
    senderFee: BigNumber,
    receiverFee: BigNumber): Promise<BigNumber> {
    await escrow.connect(_receiver).payArbitrationFeeByReceiver(_transactionID, { value: receiverFee });
    const txResponse = await escrow.connect(_sender).payArbitrationFeeBySender(
      _transactionID, { value: senderFee });

    const event = await utils.findEventByName(txResponse, 'Dispute');
    expect(event.args).to.not.be.empty;
    const { _disputeID } = event.args!;
    return _disputeID;
  }

  it('Creating transaction with arbitrage', async () => {
    let amount = ethers.utils.parseEther('0.002');
    let _transactionID = await createTransaction(sender, receiver, amount);

    const senderFee = ethers.utils.parseEther('0.0001');
    const receiverFee = ethers.utils.parseEther('0.0002');
    const receiverArbitrationFee = receiverFee <= arbitrationPrice ? receiverFee : arbitrationPrice;
    let _disputeID = await createDispute(_transactionID, sender, receiver, senderFee, receiverFee);

    await expect(escrow.connect(sender).pay(_transactionID, amount)).to.revertedWith(
      "The transaction shouldn't be disputed.");

    await expect(arbitrator.connect(court).giveRuling(_disputeID, constants.SENDER_WINS)).to.be.rejectedWith(
      'wnable: caller is not the owner');

    await arbitrator.transferOwnership(court.address);

    let platformBalance = await platform.getBalance();
    let senderBalance = await sender.getBalance();
    let receiverBalance = await receiver.getBalance();

    await arbitrator.connect(court).giveRuling(_disputeID, constants.SENDER_WINS);

    // SENDER_WINS -> no platform fee
    expect(await platform.getBalance()).to.be.equal(platformBalance);
    expect(await sender.getBalance()).to.be.equal(senderBalance.add(receiverArbitrationFee).add(amount));
    expect(await receiver.getBalance()).to.be.equal(receiverBalance);

    // new Transaction
    amount = ethers.utils.parseEther('0.005');
    _transactionID = await createTransaction(sender, receiver, amount);

    // new Dispute
    _disputeID = await createDispute(_transactionID, sender, receiver, senderFee, receiverFee);

    platformBalance = await platform.getBalance();
    senderBalance = await sender.getBalance();
    receiverBalance = await receiver.getBalance();

    // RECEIVER_WINS -> platform gains
    await arbitrator.connect(court).giveRuling(_disputeID, constants.RECEIVER_WINS);

    const platformGain = (await platform.getBalance()).sub(platformBalance);
    const feeAmount = amount.mul(constants.FEE_RECIPIENT_BASISPOINT).div(10000);
    expect(platformGain).to.be.equal(feeAmount);

    expect(await sender.getBalance()).to.be.equal(senderBalance);

    const receiverGain = (await receiver.getBalance()).sub(receiverBalance);
    const expectedGain = receiverArbitrationFee.add(amount).sub(feeAmount);
    expect(receiverGain).to.be.equal(expectedGain);
  });
});
