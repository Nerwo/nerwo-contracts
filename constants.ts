import { Wallet, parseEther } from 'ethers';

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

export const FEE_TIMEOUT = 604800n;
export const FEE_RECIPIENT_BASISPOINT = parseInt(process.env.NERWO_FEE_RECIPIENT_BASISPOINT);

export const ARBITRATOR_PRICE = parseEther(process.env.NERWO_ARBITRATION_PRICE);
export const COURT = process.env.NERWO_COURT_ADDRESS ?
    process.env.NERWO_COURT_ADDRESS.split(',').map((address: string) => address.trim()) : undefined;

export const TOKENS_WHITELIST = process.env.NERWO_TOKENS_WHITELIST ?
    process.env.NERWO_TOKENS_WHITELIST.split(',').map((address: string) => new TokenAllow(address.trim(), true))
    : [];

export function getTokenWhitelist(usdt?: string | undefined) {
    let whitelist = TOKENS_WHITELIST;

    if (!whitelist.length && usdt) {
        // whitelist our test token if deployed
        whitelist = [new TokenAllow(usdt, true)];

        // add some for gas calculation
        if (process.env.REPORT_GAS) {
            for (let i = 0; i < 2; i++) {
                whitelist.push(new TokenAllow(Wallet.createRandom().address, true));
            }
        }
    };
    return whitelist;
}
