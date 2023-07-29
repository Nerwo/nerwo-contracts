import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';
import { BaseContract, ContractRunner, Signer, ZeroAddress } from 'ethers';
import { anyUint } from '@nomicfoundation/hardhat-chai-matchers/withArgs';

import { NerwoCentralizedArbitrator, NerwoEscrow, NerwoTetherToken } from '../typechain-types';

export class Actor {
    public is_client: boolean;

    constructor() {
        this.is_client = false;
    }

    toggle() {
        this.is_client = !this.is_client;
    }
}

export const NativeToken = ZeroAddress;

export async function getContract<T extends BaseContract>(contractName: string, signer?: Signer): Promise<T> {
    const deployment = await deployments.get(contractName);
    const contract = await ethers.getContractAt(contractName, deployment.address, signer);
    return contract as unknown as T;
}

export async function getContracts() {
    const proxy: NerwoCentralizedArbitrator = await getContract('NerwoCentralizedArbitrator');
    const escrow: NerwoEscrow = await getContract('NerwoEscrow');
    const usdt: NerwoTetherToken = await getContract('NerwoTetherToken');

    return { proxy, escrow, usdt };
}

export async function getSigners() {
    const [deployer, platform, court, client, freelancer] = await ethers.getSigners();
    return { deployer, platform, court, client, freelancer };
}

export async function createTransaction(
    client: ContractRunner,
    receiver_address: string,
    token: NerwoTetherToken,
    amount = 0n,
    approve = true) {

    const blockNumber = await ethers.provider.getBlockNumber();

    const { escrow } = await getContracts();
    const { platform } = await getSigners();

    await token.connect(client).mint(amount);
    if (approve) {
        await token.connect(client).approve(await escrow.getAddress(), amount);
    }

    await expect(escrow.connect(client).createTransaction(
        await token.getAddress(), amount, receiver_address))
        .to.changeTokenBalances(
            token,
            [platform, client],
            [0, -amount]
        )
        .to.emit(escrow, 'TransactionCreated');

    const events = await escrow.queryFilter(escrow.filters.TransactionCreated(), blockNumber);
    expect(events).to.be.an('array');
    expect(events.at(-1)?.args?.transactionID).is.not.undefined;

    return events.at(-1)!.args!.transactionID!;
}

export async function createNativeTransaction(
    client: ContractRunner,
    receiver_address: string,
    amount = 0n) {

    const blockNumber = await ethers.provider.getBlockNumber();

    const { escrow } = await getContracts();
    const { platform } = await getSigners();

    await expect(escrow.connect(client).createTransaction(
        ZeroAddress, amount, receiver_address, { value: amount }))
        .to.changeEtherBalances(
            [platform, client],
            [0, -amount]
        )
        .to.emit(escrow, 'TransactionCreated');

    const events = await escrow.queryFilter(escrow.filters.TransactionCreated(), blockNumber);
    expect(events).to.be.an('array');
    expect(events.at(-1)?.args?.transactionID).is.not.undefined;

    return events.at(-1)!.args!.transactionID!;
}

export async function createDispute(actor: Actor, usdt: NerwoTetherToken | null = null) {
    const { escrow, proxy } = await getContracts();
    const { platform, court, client, freelancer } = await getSigners();

    const amount = await randomAmount();
    const arbitrationPrice = await escrow.getArbitrationCost();

    const transactionID = await ((usdt !== null) ? createTransaction(client, freelancer.address, usdt, amount) :
        createNativeTransaction(client, freelancer.address, amount));

    const payByClient = () => escrow.connect(client)
        .payArbitrationFee(transactionID, { value: arbitrationPrice });

    const payByFreelancer = () => escrow.connect(freelancer)
        .payArbitrationFee(transactionID, { value: arbitrationPrice });

    actor.toggle();

    await expect(actor.is_client ? payByClient() : payByFreelancer())
        .to.changeEtherBalances(
            [escrow, client, freelancer],
            [arbitrationPrice, actor.is_client ? -arbitrationPrice : 0, actor.is_client ? 0 : -arbitrationPrice]
        )
        .to.emit(escrow, 'HasToPayFee')
        .withArgs(transactionID, actor.is_client ? freelancer.address : client.address);

    await expect(actor.is_client ? payByClient() : payByFreelancer())
        .to.be.revertedWithCustomError(escrow, 'AlreadyPaid');

    const blockNumber = await ethers.provider.getBlockNumber();

    await expect(actor.is_client ? payByFreelancer() : payByClient())
        .to.changeEtherBalances(
            [escrow, proxy, client, freelancer],
            [0, arbitrationPrice, actor.is_client ? 0 : -arbitrationPrice, actor.is_client ? -arbitrationPrice : 0]
        )
        .to.emit(proxy, 'Dispute')
        .to.emit(escrow, 'DisputeCreated')
        .withArgs(transactionID, anyUint, actor.is_client ? client.address : freelancer.address)
        .to.not.emit(escrow, 'HasToPayFee');

    const events = await proxy.queryFilter(proxy.filters.Dispute(), blockNumber);
    expect(events).to.be.an('array');
    expect(events.at(-1)?.args?._disputeID).is.not.undefined;
    const disputeID = events.at(-1)!.args!._disputeID!;
    return {
        escrow, proxy, platform, court, client, freelancer,
        transactionID, disputeID, amount
    };
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
