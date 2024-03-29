import * as constants from './constants';

export function arbitratorArgs(owner: string | undefined) {
    return [
        process.env.NERWO_OWNER_ADDRESS || owner,
        constants.ARBITRATOR_PRICE
    ];
}

export function escrowArgs(
    owner: string | undefined,
    proxy: string | undefined,
    feeRecipient: string | undefined,
    usdt?: string | undefined) {

    const whitelist = constants.getTokenWhitelist(usdt);

    return [
        process.env.NERWO_OWNER_ADDRESS || owner,               /* newOwner */
        [
            process.env.NERWO_ARBITRATOR_ADDRESS || proxy,      /* arbitrator */
            process.env.NERWO_ARBITRATORPROXY_ADDRESS || proxy, /* arbitratorProxy */
        ],
        process.env.NERWO_ARBITRATOR_METAEVIDENCEURI || '',     /* metaEvidenceURI */
        process.env.NERWO_PLATFORM_ADDRESS || feeRecipient,     /* feeRecipient */
        constants.FEE_RECIPIENT_BASISPOINT,                     /* feeRecipientBasisPoint */
        whitelist                                               /* tokensWhitelist */
    ];
}
