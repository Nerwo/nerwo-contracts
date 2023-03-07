import { ethers } from 'hardhat';
const { parseEther } = ethers.utils;

export const SENDER_WINS = 1;
export const RECEIVER_WINS = 2;

export const MINIMAL_AMOUNT = parseEther(process.env.NERWO_MINIMAL_AMOUNT);

export const FEE_TIMEOUT = process.env.NERWO_FEE_TIMEOUT;

export const FEE_PRICE_THRESHOLDS = process.env.NERWO_FEE_PRICE_THRESHOLDS.split(';').map((tuple: string) => {
    const [amount, basisPoint] = tuple.split('=');
    return { maxPrice: parseEther(amount), feeBasisPoint: basisPoint };
});

export const TIMEOUT_PAYMENT = 1500;

export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

export const ARBITRATOR_PRICE = ethers.utils.parseEther(process.env.NERWO_ARBITRATION_PRICE);

export const enum RogueAction {
    None,
    Pay,
    Reimburse,
    ExecuteTransaction,
    PayArbitrationFeeBySender,
    Revert
}
