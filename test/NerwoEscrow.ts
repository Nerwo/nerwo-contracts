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
    rogue = await Rogue.deploy(escrow.address);
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

  async function logBalance(name: string, target: SignerWithAddress | Rogue) {
    console.log(`${name} balance: ${ethers.utils.formatEther(await target.getBalance())}`);
  }

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
    const amount = ethers.utils.parseEther('0.001');
    const platformFee = amount.mul(constants.FEE_RECIPIENT_BASISPOINT).div(10000);

    const _transactionID = await createTransaction(sender, receiver, amount);

    await expect(escrow.connect(sender).pay(_transactionID, amount))
      .to.changeEtherBalances(
        [platform, receiver],
        [platformFee, amount.sub(platformFee)]
      )
      .to.not.emit(escrow, 'SendFailed');
  });

  it('Creating transaction with rogue, then pay', async () => {
    const amount = ethers.utils.parseEther('0.002');
    const payAmount = amount.div(2);
    const platformFee = payAmount.mul(constants.FEE_RECIPIENT_BASISPOINT).div(10000);

    const _transactionID = await createTransaction(sender, rogue, amount);

    await rogue.setAction(constants.RogueAction.Pay);
    await rogue.setTransaction(_transactionID);
    await rogue.setAmount(payAmount);

    await expect(escrow.connect(sender).pay(_transactionID, payAmount))
      .to.changeEtherBalances(
        [platform, rogue],
        [platformFee, 0]
      )
      .to.emit(escrow, 'SendFailed');

    await rogue.setAction(constants.RogueAction.None);
    await expect(escrow.connect(sender).pay(_transactionID, payAmount))
      .to.changeEtherBalances(
        [platform, rogue],
        [platformFee, payAmount.sub(platformFee)]
      )
      .to.not.emit(escrow, 'SendFailed');
  });

  async function createDispute(
    _transactionID: BigNumber,
    _sender: SignerWithAddress,
    _receiver: SignerWithAddress,
    senderFee: BigNumber,
    receiverFee: BigNumber): Promise<BigNumber> {

    await expect(await escrow.connect(_receiver).payArbitrationFeeByReceiver(
      _transactionID, { value: receiverFee })).to.emit(escrow, 'HasToPayFee');

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

    let _disputeID = await createDispute(_transactionID, sender, receiver, arbitrationPrice, arbitrationPrice);

    await expect(escrow.connect(sender).pay(_transactionID, amount)).to.revertedWith(
      "The transaction shouldn't be disputed.");

    await expect(arbitrator.connect(court).giveRuling(_disputeID, constants.SENDER_WINS)).to.be.rejectedWith(
      'Ownable: caller is not the owner');

    await arbitrator.transferOwnership(court.address);

    // SENDER_WINS -> no platform fee
    await expect(arbitrator.connect(court).giveRuling(_disputeID, constants.SENDER_WINS))
      .to.changeEtherBalances(
        [platform, sender, receiver],
        [0, arbitrationPrice.add(amount), 0]
      )
      .to.emit(escrow, 'Ruling');

    // new Transaction
    amount = ethers.utils.parseEther('0.005');
    _transactionID = await createTransaction(sender, receiver, amount);

    // new Dispute
    _disputeID = await createDispute(_transactionID, sender, receiver, arbitrationPrice, arbitrationPrice);

    const feeAmount = amount.mul(constants.FEE_RECIPIENT_BASISPOINT).div(10000);
    // RECEIVER_WINS -> platform gains
    await expect(arbitrator.connect(court).giveRuling(_disputeID, constants.RECEIVER_WINS))
      .to.changeEtherBalances(
        [platform, sender, receiver],
        [feeAmount, 0, arbitrationPrice.add(amount).sub(feeAmount)]
      )
      .to.emit(escrow, 'Ruling');
  });

  it('Creating arbitrage transaction with rogue', async () => {
    await arbitrator.transferOwnership(court.address);

    // fund rogue contract
    const rogueFunds = ethers.utils.parseEther('10.0');
    await expect(sender.sendTransaction({ to: rogue.address, value: rogueFunds }))
      .to.changeEtherBalance(rogue, rogueFunds);

    let amount = ethers.utils.parseEther('0.007');
    await rogue.setAmount(amount);
    let tx = await rogue.createTransaction(
      constants.TIMEOUT_PAYMENT,
      receiver.address,
      'evidence');

    let event = await utils.findEventByName(tx, 'TransactionCreated');

    expect(event.args).to.not.be.empty;
    const { _transactionID } = event.args!;

    await expect(escrow.connect(receiver).payArbitrationFeeByReceiver(_transactionID, {
      value: arbitrationPrice.mul(2)
    })).to.be.rejectedWith('The receiver fee must cover arbitration costs.');

    await expect(escrow.connect(receiver).payArbitrationFeeByReceiver(
      _transactionID, { value: arbitrationPrice }))
      .to.changeEtherBalances(
        [escrow, receiver],
        [arbitrationPrice, -arbitrationPrice]
      );

    await rogue.setAction(constants.RogueAction.PayArbitrationFeeBySender);
    await rogue.setTransaction(_transactionID);
    await rogue.setAmount(arbitrationPrice.mul(2));

    await expect(rogue.payArbitrationFeeBySender(_transactionID))
      .to.be.rejectedWith('The sender fee must cover arbitration costs.');

    await rogue.setAmount(arbitrationPrice);

    let _disputeID: BigNumber | undefined;

    await expect(async () => {
      tx = await rogue.payArbitrationFeeBySender(_transactionID);
      event = await utils.findEventByName(tx, 'Dispute');
      ({ _disputeID } = event.args!);
      return tx;
    }).to.changeEtherBalance(rogue, -arbitrationPrice);

    expect(_disputeID).to.not.be.undefined;

    await rogue.setAction(constants.RogueAction.Revert);
    await expect(arbitrator.connect(court).giveRuling(_disputeID!, constants.SENDER_WINS))
      .to.changeEtherBalances(
        [platform, rogue, receiver],
        [0, 0, 0])
      .to.emit(escrow, 'SendFailed');
  });
});
