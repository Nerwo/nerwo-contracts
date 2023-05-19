import { ethers } from 'hardhat';

const { parseEther } = ethers.utils;

export const SENDER_WINS = 1;
export const RECEIVER_WINS = 2;

export const FEE_TIMEOUT = parseInt(process.env.NERWO_FEE_TIMEOUT, 10);
export const FEE_RECIPIENT_BASISPOINT = parseInt(process.env.NERWO_FEE_RECIPIENT_BASISPOINT);

export const ARBITRATOR_PRICE = parseEther(process.env.NERWO_ARBITRATION_PRICE);
export const TOKENS_WHITELIST = process.env.NERWO_TOKENS_WHITELIST?.split(',') ?? [];

export const enum RogueAction {
    None,
    Pay,
    Reimburse,
    ExecuteTransaction,
    PayArbitrationFeeBySender,
    Revert
}
