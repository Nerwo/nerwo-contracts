import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';
import { BaseContract, ContractRunner, Interface, Signer } from 'ethers';

import { ClaimableToken, NerwoCentralizedArbitrator, NerwoEscrow, NerwoTetherToken } from '../typechain-types';

export async function getContract<T extends BaseContract>(contractName: string, signer?: Signer): Promise<T> {
    const deployment = await deployments.get(contractName);
    const contract = await ethers.getContractAt(contractName, deployment.address, signer);
    return contract as unknown as T;
}

export async function getContracts() {
    const arbitrator: NerwoCentralizedArbitrator = await getContract('NerwoCentralizedArbitrator');
    const escrow: NerwoEscrow = await getContract('NerwoEscrow');
    const usdt: NerwoTetherToken = await getContract('NerwoTetherToken');

    return { arbitrator, escrow, usdt };
}

export async function getSigners() {
    const [deployer, platform, court, sender, receiver] = await ethers.getSigners();
    return { deployer, platform, court, sender, receiver };
}

export async function createTransaction(
    sender: ContractRunner,
    receiver_address: string,
    token: ClaimableToken,
    amount: bigint = 0n,
    metaEvidence = '') {

    const blockNumber = await ethers.provider.getBlockNumber();

    const { escrow } = await getContracts();
    const { platform } = await getSigners();

    await token.connect(sender).claim(amount);
    await token.connect(sender).approve(await escrow.getAddress(), amount);

    await expect(escrow.connect(sender).createTransaction(
        await token.getAddress(), amount, receiver_address, metaEvidence))
        .to.changeTokenBalances(
            token,
            [platform, sender],
            [0, -amount]
        )
        .to.emit(escrow, 'TransactionCreated');

    const events = await escrow.queryFilter(escrow.filters.TransactionCreated(), blockNumber);
    expect(events).to.be.an('array');
    expect(events.at(-1)?.args?._transactionID).is.not.undefined;

    return events.at(-1)!.args!._transactionID!;
}

export async function createDispute(sender: Signer, receiver: Signer, transactionID: bigint) {
    const { escrow } = await getContracts();
    const arbitrationPrice = await escrow.arbitrationCost();

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
    return 100000000000000n * BigInt(Math.floor(100000 / rand()));
}

// https://ethereum.stackexchange.com/a/123567/115740
// upgraded to v6
export function getInterfaceID(contractInterface: Interface) {
    let interfaceID: bigint = 0n;

    contractInterface.forEachFunction((func => {
        interfaceID = interfaceID ^ BigInt(func.selector);
    }));

    return `0x${interfaceID.toString(16).padStart(8, '0')}`;
}
