import { ZeroAddress, parseEther } from 'ethers';

export const enum Ruling {
    SplitAmount = 0,
    ClientWins = 1,
    FreelanceWins = 2
}

export const FEE_TIMEOUT = parseInt(process.env.NERWO_FEE_TIMEOUT, 10);
export const FEE_RECIPIENT_BASISPOINT = parseInt(process.env.NERWO_FEE_RECIPIENT_BASISPOINT);

export const ARBITRATOR_PRICE = parseEther(process.env.NERWO_ARBITRATION_PRICE);

export const TOKENS_WHITELIST = process.env.NERWO_TOKENS_WHITELIST ?
    process.env.NERWO_TOKENS_WHITELIST.split(',').map((address: string) => address.trim())
    : [];

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
