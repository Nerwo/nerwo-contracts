import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber, Contract, Signer, Wallet } from 'ethers';
import { Interface } from 'ethers/lib/utils';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { ClaimableToken, NerwoCentralizedArbitrator, NerwoEscrow, TetherToken } from '../typechain-types';

type Account = Contract | Wallet;

export async function getContracts() {
    const arbitrator: NerwoCentralizedArbitrator = await ethers.getContract('NerwoCentralizedArbitrator');
    const escrow: NerwoEscrow = await ethers.getContract('NerwoEscrow');
    const usdt: TetherToken = await ethers.getContract('TetherToken');

    return { arbitrator, escrow, usdt };
}

export async function getSigners() {
    const [deployer, platform, court, sender, receiver] = await ethers.getSigners();
    return { deployer, platform, court, sender, receiver };
}

export async function fund(recipient: Account, amount: BigNumber) {
    const { deployer } = await getSigners();
    await expect(deployer.sendTransaction({ to: recipient.address, value: amount }))
        .to.changeEtherBalance(recipient, amount);
}

export async function createTransaction(
    sender: SignerWithAddress,
    receiver_address: string,
    token: ClaimableToken,
    amount: BigNumber,
    metaEvidence = '') {

    const blockNumber = await ethers.provider.getBlockNumber();

    const { escrow } = await getContracts();
    const { platform } = await getSigners();

    await token.connect(sender).claim(amount);
    await token.connect(sender).approve(escrow.address, amount);

    await expect(escrow.connect(sender).createTransaction(
        token.address, amount, receiver_address, metaEvidence))
        .to.changeTokenBalances(
            token,
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

    await expect(escrow.connect(sender).payArbitrationFeeBySender(
        transactionID, { value: arbitrationPrice }))
        .to.emit(escrow, 'HasToPayFee');

    const blockNumber = await ethers.provider.getBlockNumber();

    await expect(escrow.connect(receiver).payArbitrationFeeByReceiver(
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

// https://ethereum.stackexchange.com/a/123567/115740
export function getInterfaceID(contractInterface: Interface) {
    let interfaceID: BigNumber = ethers.constants.Zero;
    const functions: string[] = Object.keys(contractInterface.functions);

    for (let i = 0; i < functions.length; i++) {
        interfaceID = interfaceID.xor(contractInterface.getSighash(functions[i]));
    }

    return interfaceID.toHexString();
}
