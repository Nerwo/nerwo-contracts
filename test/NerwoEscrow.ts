import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { BigNumber } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ContractTransaction, Event } from '@ethersproject/contracts';

import { NerwoCentralizedArbitratorV1, NerwoEscrowV1 } from '../typechain-types';

//import { NerwoCentralizedArbitratorV1 } from '../typechain-types';
//import { NerwoCentralizedArbitratorV1Interface } from '../typechain-types/contracts/v2/uups/NerwoCentralizedArbitratorV1';

const SENDER_WINS = 1;
const RECEIVER_WINS = 2;

const FEE_TIMEOUT = 302400;
const FEE_RECIPIENT_BASISPOINT = 550;

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

async function findEventByName(txResponse: ContractTransaction, name: string): Promise<Event> {
  const txReceipt = await txResponse.wait();

  expect(txReceipt.events).to.be.an('array').that.is.not.empty;

  const event = txReceipt.events!.find(event => event.event === name);
  expect(event).to.not.be.undefined;

  return event!;
}

describe('NerwoEscrow', function () {
  const arbitrationPrice = ethers.utils.parseEther('0.0001');
  let escrow: NerwoEscrowV1;
  let arbitrator: NerwoCentralizedArbitratorV1;
  let platform: SignerWithAddress, court: SignerWithAddress;
  let sender: SignerWithAddress, receiver: SignerWithAddress;

  this.beforeEach(async () => {
    const ARBITRATOR_PRICE = ethers.utils.parseEther(process.env.NERWO_ARBITRATION_PRICE);
    const NerwoCentralizedArbitratorV1 = await ethers.getContractFactory("NerwoCentralizedArbitratorV1");
    arbitrator = await upgrades.deployProxy(NerwoCentralizedArbitratorV1, [ARBITRATOR_PRICE], {
      kind: 'uups',
      initializer: 'initialize',
    }) as NerwoCentralizedArbitratorV1;
    arbitrator.deployed();

    const ARGS = [
      ZERO_ADDRESS,
      [], // _arbitratorExtraData
      ZERO_ADDRESS,
      0,
      0
    ]

    const NerwoEscrowV1 = await ethers.getContractFactory("NerwoEscrowV1");
    escrow = await upgrades.deployProxy(NerwoEscrowV1, ARGS, {
      kind: 'uups',
      initializer: 'initialize',
    }) as NerwoEscrowV1;
    escrow.deployed();

    [, platform, court, sender, receiver] = await ethers.getSigners();

    await escrow.transferOwnership(platform.address);
    await escrow.connect(platform).setArbitrator(arbitrator.address, [], platform.address, FEE_RECIPIENT_BASISPOINT, FEE_TIMEOUT);
  });

  async function createTransaction(amount: BigNumber): Promise<BigNumber> {
    const txResponse = await escrow.connect(sender).createTransaction(
      1500, receiver.address, 'evidence',
      { value: amount });

    const event = await findEventByName(txResponse, 'TransactionCreated');
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
    const expectedFee = amount.mul(FEE_RECIPIENT_BASISPOINT).div(10000);
    expect(platformGain).to.be.equal(expectedFee);

    const receiverGain = (await receiver.getBalance()).sub(receiverBalance);
    expect(receiverGain).to.be.equal(amount.sub(expectedFee));
  });

  async function createDispute(_transactionID: BigNumber, senderFee: BigNumber,
    receiverFee: BigNumber): Promise<BigNumber> {
    await escrow.connect(receiver).payArbitrationFeeByReceiver(_transactionID, { value: receiverFee });
    const txResponse = await escrow.connect(sender).payArbitrationFeeBySender(
      _transactionID, { value: senderFee });

    const event = await findEventByName(txResponse, 'Dispute');
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

    await expect(arbitrator.connect(court).giveRuling(_disputeID, SENDER_WINS)).to.be.rejectedWith(
      'wnable: caller is not the owner');

    await arbitrator.transferOwnership(court.address);

    let platformBalance = await platform.getBalance();
    let senderBalance = await sender.getBalance();
    let receiverBalance = await receiver.getBalance();

    await arbitrator.connect(court).giveRuling(_disputeID, SENDER_WINS);

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
    await arbitrator.connect(court).giveRuling(_disputeID, RECEIVER_WINS);

    const platformGain = (await platform.getBalance()).sub(platformBalance);
    const feeAmount = amount.mul(FEE_RECIPIENT_BASISPOINT).div(10000);
    expect(platformGain).to.be.equal(feeAmount);

    expect(await sender.getBalance()).to.be.equal(senderBalance);

    const receiverGain = (await receiver.getBalance()).sub(receiverBalance);
    const expectedGain = receiverArbitrationFee.add(amount).sub(feeAmount);
    expect(receiverGain).to.be.equal(expectedGain);
  });
});
