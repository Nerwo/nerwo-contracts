import { ZeroAddress, parseEther } from 'ethers';

export const SENDER_WINS = 1;
export const RECEIVER_WINS = 2;

export const FEE_TIMEOUT = parseInt(process.env.NERWO_FEE_TIMEOUT, 10);
export const FEE_RECIPIENT_BASISPOINT = parseInt(process.env.NERWO_FEE_RECIPIENT_BASISPOINT);

export const ARBITRATOR_PRICE = parseEther(process.env.NERWO_ARBITRATION_PRICE);

export const TOKENS_WHITELIST = process.env.NERWO_TOKENS_WHITELIST ?
    process.env.NERWO_TOKENS_WHITELIST.split(',').map((address: string) => address.trim())
    : [];

export const enum RogueAction {
    None,
    Pay,
    Reimburse,
    ExecuteTransaction,
    PayArbitrationFeeBySender,
    Revert
}

export function getTokenWhitelist(usdt?: string | undefined) {
    let whitelist = TOKENS_WHITELIST;

    if (!whitelist.length && usdt) {
        // whitelist our test token if deployed
        whitelist = [usdt];

        // fake first address, for gas calculation
        if (process.env.REPORT_GAS) {
            whitelist = [ZeroAddress, whitelist[0]];
        }
    };
    return whitelist;
}
