import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { NerwoCentralizedArbitratorV1, NerwoEscrowV1, Rogue } from '../typechain-types';

import * as constants from '../constants';

describe('NerwoEscrow: misc', function () {
  const arbitrationPrice = ethers.utils.parseEther('0.0001');
  let escrow: NerwoEscrowV1;
  let arbitrator: NerwoCentralizedArbitratorV1;
  let deployer: SignerWithAddress, platform: SignerWithAddress, court: SignerWithAddress;
  let sender: SignerWithAddress, receiver: SignerWithAddress;
  let rogue: Rogue;

  this.beforeEach(async () => {
    [deployer, platform, court, sender, receiver] = await ethers.getSigners();

    process.env.NERWO_COURT_ADDRESS = deployer.address;
    await deployments.fixture(['NerwoCentralizedArbitratorV1', 'NerwoEscrowV1']);

    let deployment = await deployments.get('NerwoCentralizedArbitratorV1');
    arbitrator = await ethers.getContractAt('NerwoCentralizedArbitratorV1', deployment.address);

    deployment = await deployments.get('NerwoEscrowV1');
    escrow = await ethers.getContractAt('NerwoEscrowV1', deployment.address);

    const Rogue = await ethers.getContractFactory("Rogue");
    rogue = await Rogue.deploy(escrow.address);
    await rogue.deployed();
  });

  it('Updating priceThresholds', async () => {
    const answer = ethers.BigNumber.from(42);
    const priceThreshold = {
      maxPrice: answer,
      feeBasisPoint: 0
    };

    expect((await escrow.priceThresholds(1)).maxPrice)
      .to.be.equal(constants.FEE_PRICE_THRESHOLDS[1].maxPrice);

    await escrow.connect(deployer).setPriceThresholds([priceThreshold]);
    expect((await escrow.priceThresholds(0)).maxPrice).to.be.equal(answer);

    await expect(escrow.priceThresholds(1))
      .to.be.revertedWithoutReason();

    // for avg gas calc
    await escrow.connect(deployer).setPriceThresholds(constants.FEE_PRICE_THRESHOLDS);
  });

  it('Creating transaction, then pay', async () => {
    const amount = ethers.utils.parseEther('0.01');
    const platformFee = await escrow.calculateFeeRecipientAmount(amount);

    const blockNumber = await ethers.provider.getBlockNumber();
    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT, receiver.address, '', { value: amount }))
      .to.changeEtherBalances(
        [platform, sender],
        [0, amount.mul(-1)]
      )
      .to.emit(escrow, 'TransactionCreated');

    const events = await escrow.queryFilter(escrow.filters.TransactionCreated(), blockNumber);
    expect(events).to.be.an('array').that.lengthOf(1);
    expect(events[0].args!).is.not.undefined;

    const { _transactionID } = events[0].args!;

    await expect(escrow.connect(sender).pay(_transactionID, amount))
      .to.changeEtherBalances(
        [platform, receiver],
        [platformFee, amount.sub(platformFee)]
      )
      .to.not.emit(escrow, 'SendFailed');
  });

  it('Creating transaction with rogue, then pay', async () => {
    const amount = ethers.utils.parseEther('0.02');
    const payAmount = amount.div(2);
    const platformFee = await escrow.calculateFeeRecipientAmount(payAmount);

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

  it('Creating transaction with arbitrage', async () => {
    let amount = ethers.utils.parseEther('0.04');

    let blockNumber = await ethers.provider.getBlockNumber();
    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT, receiver.address, '', { value: amount }))
      .to.changeEtherBalances(
        [platform, sender],
        [0, amount.mul(-1)]
      )
      .to.emit(escrow, 'TransactionCreated');

    let cEvents = await escrow.queryFilter(escrow.filters.TransactionCreated(), blockNumber);
    expect(cEvents).to.be.an('array').that.lengthOf(1);
    expect(cEvents[0].args!).is.not.undefined;
    let { _transactionID } = cEvents[0].args!;

    await expect(await escrow.connect(receiver).payArbitrationFeeByReceiver(
      _transactionID, { value: arbitrationPrice }))
      .to.emit(escrow, 'HasToPayFee');

    blockNumber = await ethers.provider.getBlockNumber();
    await expect(escrow.connect(sender).payArbitrationFeeBySender(
      _transactionID, { value: arbitrationPrice }))
      .to.emit(escrow, 'Dispute')
      .to.not.emit(escrow, 'HasToPayFee');

    let dEvents = await escrow.queryFilter(escrow.filters.Dispute(), blockNumber);
    expect(dEvents).to.be.an('array').that.lengthOf(1);
    expect(dEvents[0].args!).is.not.undefined;
    let { _disputeID } = dEvents[0].args!

    await expect(escrow.connect(sender).pay(_transactionID, amount))
      .to.revertedWithCustomError(escrow, 'InvalidStatus');

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
    amount = ethers.utils.parseEther('0.08');

    blockNumber = await ethers.provider.getBlockNumber();

    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT, receiver.address, '', { value: amount }))
      .to.changeEtherBalances(
        [platform, sender],
        [0, amount.mul(-1)]
      )
      .to.emit(escrow, 'TransactionCreated');

    cEvents = await escrow.queryFilter(escrow.filters.TransactionCreated(), blockNumber);
    expect(cEvents).to.be.an('array').that.lengthOf(1);
    expect(cEvents[0].args!).is.not.undefined;

    ({ _transactionID } = cEvents[0].args!);

    await expect(escrow.connect(receiver).payArbitrationFeeByReceiver(
      _transactionID, { value: arbitrationPrice }))
      .to.changeEtherBalances(
        [escrow, receiver],
        [arbitrationPrice, arbitrationPrice.mul(-1)]
      )
      .to.emit(escrow, 'HasToPayFee')
      .to.not.emit(escrow, 'Dispute');

    blockNumber = await ethers.provider.getBlockNumber();
    await expect(escrow.connect(sender).payArbitrationFeeBySender(
      _transactionID, { value: arbitrationPrice }))
      .to.emit(escrow, 'Dispute')
      .to.not.emit(escrow, 'HasToPayFee');

    dEvents = await escrow.queryFilter(escrow.filters.Dispute(), blockNumber);
    expect(dEvents).to.be.an('array').that.lengthOf(1);
    expect(dEvents[0].args!).is.not.undefined;
    ({ _disputeID } = dEvents[0].args!);

    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);
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

    let amount = ethers.utils.parseEther('0.07');
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
    expect(events).to.be.an('array').that.lengthOf(1);
    expect(events[0].args!).is.not.undefined;

    const { _transactionID } = events[0].args!;

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
    expect(dEvents).to.be.an('array').that.lengthOf(1);
    expect(dEvents[0].args!).is.not.undefined;
    const { _disputeID } = dEvents[0].args!;

    await rogue.setAction(constants.RogueAction.Revert);
    await expect(arbitrator.connect(court).giveRuling(_disputeID!, constants.SENDER_WINS))
      .to.changeEtherBalances(
        [platform, rogue, receiver],
        [0, 0, 0])
      .to.emit(escrow, 'SendFailed');
  });
});
