import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber, Contract, Signer, Wallet } from 'ethers';
import { Interface } from 'ethers/lib/utils';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { ClaimableToken, NerwoCentralizedArbitrator, NerwoEscrow, NerwoTetherToken } from '../typechain-types';

type Account = Contract | Wallet;

export async function getContracts() {
    const arbitrator: NerwoCentralizedArbitrator = await ethers.getContract('NerwoCentralizedArbitrator');
    const escrow: NerwoEscrow = await ethers.getContract('NerwoEscrow');
    const usdt: NerwoTetherToken = await ethers.getContract('NerwoTetherToken');

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
    amount: BigNumber = BigNumber.from(0),
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

function sfc32(a: number, b: number, c: number, d: number) {
    return function () {
        a >>>= 0; b >>>= 0; c >>>= 0; d >>>= 0;
        let t = (a + b) | 0;
        a = b ^ b >>> 9;
        b = c + (c << 3) | 0;
        c = (c << 21 | c >>> 11);
        d = d + 1 | 0;
        t = t + d | 0;
        c = c + t | 0;
        return (t >>> 0) / 4294967296;
    };
}

// a real random function screws gas calculations
const rand = sfc32(0x9e3779b9, 0x243f6a88, 0xb7e15162, 42 ^ 1337);

export async function randomAmount() {
    const minimalAmount = BigNumber.from(100000000000000);
    return minimalAmount.mul(Math.floor(100000 / rand()));
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
