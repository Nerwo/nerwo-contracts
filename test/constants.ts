import { ethers } from 'hardhat';

export const SENDER_WINS = 1;
export const RECEIVER_WINS = 2;

export const FEE_TIMEOUT = 302400;
export const FEE_RECIPIENT_BASISPOINT = 550;

export const TIMEOUT_PAYMENT = 1500;

export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

export const ARBITRATOR_PRICE = ethers.utils.parseEther(process.env.NERWO_ARBITRATION_PRICE);
