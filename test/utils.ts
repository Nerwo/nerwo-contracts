import { expect } from 'chai';
import { BigNumber, Contract, Signer, Wallet } from 'ethers';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { NerwoCentralizedArbitrator, NerwoEscrow, Rogue } from '../typechain-types';

import * as constants from '../constants';

type Account = Contract | Wallet;

export async function getContracts() {
    const arbitrator: NerwoCentralizedArbitrator = await ethers.getContract('NerwoCentralizedArbitrator');
    const escrow: NerwoEscrow = await ethers.getContract('NerwoEscrow');
    const rogue: Rogue = await ethers.getContract('Rogue');

    return { arbitrator, escrow, rogue };
}

export async function getSigners() {
    const [deployer, platform, court, sender, receiver] = await ethers.getSigners();
    return { deployer, platform, court, sender, receiver };
}

export async function fund(recipient: Account, amount: BigNumber) {
    const { deployer } = await getSigners();
    expect(await deployer.sendTransaction({ to: recipient.address, value: amount }))
        .to.changeEtherBalance(recipient, amount);
}

export async function createTransaction(
    sender: SignerWithAddress,
    receiver_address: string,
    amount: BigNumber,
    timeoutPayment = constants.TIMEOUT_PAYMENT,
    metaEvidence = '') {

    const blockNumber = await ethers.provider.getBlockNumber();

    const { escrow } = await getContracts();
    const { platform } = await getSigners();

    expect(await escrow.connect(sender).createTransaction(
        timeoutPayment, receiver_address, metaEvidence, { value: amount }))
        .to.changeEtherBalances(
            [platform, sender],
            [0, amount.mul(-1)]
        )
        .to.emit(escrow, 'TransactionCreated');

    const events = await escrow.queryFilter(escrow.filters.TransactionCreated(), blockNumber);
    expect(events).to.be.an('array');
    expect(events.at(-1)?.args?._transactionID).is.not.undefined;

    return events.at(-1)!.args!._transactionID!;
}

export async function createDispute(sender: Signer, receiver: Signer, transactionID: BigNumber) {
    const { arbitrator, escrow } = await getContracts();
    const arbitrationPrice = await arbitrator.arbitrationCost([]);

    expect(await escrow.connect(sender).payArbitrationFeeBySender(
        transactionID, { value: arbitrationPrice }))
        .to.emit(escrow, 'HasToPayFee');

    const blockNumber = await ethers.provider.getBlockNumber();

    expect(await escrow.connect(receiver).payArbitrationFeeByReceiver(
        transactionID, { value: arbitrationPrice }))
        .to.emit(escrow, 'Dispute')
        .to.not.emit(escrow, 'HasToPayFee');

    const events = await escrow.queryFilter(escrow.filters.Dispute(), blockNumber);
    expect(events).to.be.an('array');
    expect(events.at(-1)?.args?._disputeID).is.not.undefined;
    return events.at(-1)!.args!._disputeID!;
}

export async function randomAmount() {
    const { escrow } = await getContracts();
    const minimalAmount = await escrow.minimalAmount();
    return minimalAmount.mul(Math.floor(10 / Math.random()));
}
