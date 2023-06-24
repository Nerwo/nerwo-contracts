import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';
import { BaseContract, ContractRunner, Signer } from 'ethers';

import { NerwoCentralizedArbitrator, NerwoEscrow, NerwoTetherToken } from '../typechain-types';

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
    amount: bigint = 0n) {

    const blockNumber = await ethers.provider.getBlockNumber();

    const { escrow } = await getContracts();
    const { platform } = await getSigners();

    await token.connect(client).mint(amount);
    await token.connect(client).approve(await escrow.getAddress(), amount);

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
