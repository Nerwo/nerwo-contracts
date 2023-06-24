import * as constants from './constants';

export function arbitratorArgs(court: string | undefined) {
    return [process.env.NERWO_COURT_ADDRESS || court, constants.ARBITRATOR_PRICE];
}

export function escrowArgs(
    owner: string | undefined,
    proxy: string | undefined,
    feeRecipient: string | undefined,
    usdt?: string | undefined) {

    const whitelist = constants.getTokenWhitelist(usdt);

    return [
        process.env.NERWO_OWNER_ADDRESS || owner,           /* newOwner */
        constants.FEE_TIMEOUT,                              /* feeTimeout */
        process.env.NERWO_ARBITRATOR_ADDRESS || proxy,      /* arbitrator */
        process.env.NERWO_ARBITRATORPROXY_ADDRESS || proxy, /* arbitratorProxy */
        '0x00',                                             /* arbitratorExtraData */
        process.env.NERWO_PLATFORM_ADDRESS || feeRecipient, /* feeRecipient */
        constants.FEE_RECIPIENT_BASISPOINT,                 /* feeRecipientBasisPoint */
        whitelist                                           /* tokensWhitelist */
    ];
}
