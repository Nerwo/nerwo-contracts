import { ethers } from 'hardhat';

export const SENDER_WINS = 1;
export const RECEIVER_WINS = 2;

export const MINIMAL_AMOUNT = ethers.utils.parseEther(process.env.NERWO_MINIMAL_AMOUNT);

export const FEE_TIMEOUT = process.env.NERWO_FEE_TIMEOUT;
export const FEE_RECIPIENT_BASISPOINT = process.env.NERWO_FEE_RECIPIENT_BASISPOINT;

export const TIMEOUT_PAYMENT = 1500;

export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

export const ARBITRATOR_PRICE = ethers.utils.parseEther(process.env.NERWO_ARBITRATION_PRICE);

export const enum RogueAction {
    None,
    Pay,
    Reimburse,
    PayArbitrationFeeBySender,
    Revert
}
