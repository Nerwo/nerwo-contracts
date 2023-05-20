import * as constants from './constants';

export function arbitratorArgs(court: string) {
    return [process.env.NERWO_COURT_ADDRESS || court, constants.ARBITRATOR_PRICE];
}

export function escrowArgs(owner: string, arbitrator: string, feeRecipient: string,
    usdt?: string | undefined) {

    const whitelist = constants.getTokenWhitelist(usdt);

    return [
        process.env.NERWO_OWNER_ADDRESS || owner,           /* _owner */
        process.env.NERWO_ARBITRATOR_ADDRESS || arbitrator, /* _arbitrator */
        [],                                                 /* _arbitratorExtraData */
        constants.FEE_TIMEOUT,                              /* _feeTimeout */
        feeRecipient,                                       /* _feeRecipient */
        constants.FEE_RECIPIENT_BASISPOINT,                 /* _feeRecipientBasisPoint */
        whitelist                                           /* _tokensWhitelist */
    ];
}
