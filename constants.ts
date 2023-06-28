import { ZeroAddress, parseEther } from 'ethers';

class TokenAllow {
    constructor(public token: string, public allow: boolean) {
        this.token = token;
        this.allow = allow;
    }
}

export const enum Ruling {
    SplitAmount = 0,
    ClientWins = 1,
    FreelancerWins = 2
}

export const FEE_TIMEOUT = parseInt(process.env.NERWO_FEE_TIMEOUT, 10);
export const FEE_RECIPIENT_BASISPOINT = parseInt(process.env.NERWO_FEE_RECIPIENT_BASISPOINT);

export const ARBITRATOR_PRICE = parseEther(process.env.NERWO_ARBITRATION_PRICE);

export const TOKENS_WHITELIST = process.env.NERWO_TOKENS_WHITELIST ?
    process.env.NERWO_TOKENS_WHITELIST.split(',').map((address: string) => new TokenAllow(address.trim(), true))
    : [];

export function getTokenWhitelist(usdt?: string | undefined) {
    let whitelist = TOKENS_WHITELIST;

    if (!whitelist.length && usdt) {
        // whitelist our test token if deployed
        whitelist = [new TokenAllow(usdt, true)];

        // fake first address, for gas calculation
        if (process.env.REPORT_GAS) {
            whitelist = [new TokenAllow(ZeroAddress, true), whitelist[0]];
        }
    };
    return whitelist;
}
