import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { CentralizedArbitrator, MultipleArbitrableTransactionWithFee } from '../typechain-types';

import * as constants from './constants';
import * as utils from './utils';

describe('MultipleArbitrableTransactionWithFee', function () {
  const arbitrationPrice = ethers.utils.parseEther('0.0001');
  let escrow: MultipleArbitrableTransactionWithFee;
  let arbitrator: CentralizedArbitrator;
  let platform: SignerWithAddress, court: SignerWithAddress;
  let sender: SignerWithAddress, receiver: SignerWithAddress;

  this.beforeEach(async () => {
    const CentralizedArbitratorFactory = await ethers.getContractFactory('CentralizedArbitrator');
    arbitrator = await CentralizedArbitratorFactory.deploy(arbitrationPrice);
    await arbitrator.deployed();

    const MultipleArbitrableTransactionWithFeeFactory = await ethers.getContractFactory('MultipleArbitrableTransactionWithFee');

    [, platform, court, sender, receiver] = await ethers.getSigners();

    escrow = await MultipleArbitrableTransactionWithFeeFactory.deploy(
      constants.ZERO_ADDRESS,
      [], // _arbitratorExtraData
      constants.ZERO_ADDRESS,
      0,
      0);
    await escrow.deployed();

    await escrow.transferOwnership(platform.address);
    await escrow.connect(platform).setArbitrator(arbitrator.address,
      [], platform.address,
      constants.FEE_RECIPIENT_BASISPOINT,
      constants.FEE_TIMEOUT);
  });

  async function createTransaction(amount: BigNumber): Promise<BigNumber> {
    const txResponse = await escrow.connect(sender).createTransaction(
      1500, receiver.address, 'evidence',
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
    const _transactionID = await createTransaction(amount);

    await escrow.connect(sender).pay(_transactionID, amount);

    const platformGain = (await platform.getBalance()).sub(platformBalance);
    const expectedFee = amount.mul(constants.FEE_RECIPIENT_BASISPOINT).div(10000);
    expect(platformGain).to.be.equal(expectedFee);

    const receiverGain = (await receiver.getBalance()).sub(receiverBalance);
    expect(receiverGain).to.be.equal(amount.sub(expectedFee));
  });

  async function createDispute(_transactionID: BigNumber, senderFee: BigNumber,
    receiverFee: BigNumber): Promise<BigNumber> {
    await escrow.connect(receiver).payArbitrationFeeByReceiver(_transactionID, { value: receiverFee });
    const txResponse = await escrow.connect(sender).payArbitrationFeeBySender(
      _transactionID, { value: senderFee });

    const event = await utils.findEventByName(txResponse, 'Dispute');
    expect(event.args).to.not.be.empty;
    const { _disputeID } = event.args!;
    return _disputeID;
  }

  it('Creating transaction with arbitrage', async () => {
    let amount = ethers.utils.parseEther('0.002');
    let _transactionID = await createTransaction(amount);

    const senderFee = ethers.utils.parseEther('0.0001');
    const receiverFee = ethers.utils.parseEther('0.0002');
    const receiverArbitrationFee = receiverFee <= arbitrationPrice ? receiverFee : arbitrationPrice;
    let _disputeID = await createDispute(_transactionID, senderFee, receiverFee);

    await expect(escrow.connect(sender).pay(_transactionID, amount)).to.revertedWith(
      "The transaction shouldn't be disputed.");

    await expect(arbitrator.connect(court).giveRuling(_disputeID, constants.SENDER_WINS)).to.be.rejectedWith(
      'Can only be called by the owner.');

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
    _transactionID = await createTransaction(amount);

    // new Dispute
    _disputeID = await createDispute(_transactionID, senderFee, receiverFee);

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
