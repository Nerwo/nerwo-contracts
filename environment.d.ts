declare global {
    namespace NodeJS {
        interface ProcessEnv {
            PRIVATE_KEY: string;
            NERWO_OWNER_ADDRESS?: string;
            NERWO_COURT_ADDRESS?: string;
            NERWO_PLATFORM_ADDRESS?: string;
            NERWO_ARBITRATION_PRICE: string;
            NERWO_FEE_TIMEOUT: string;
            NERWO_FEE_RECIPIENT_BASISPOINT: string;
            NERWO_TOKENS_WHITELIST?: string;
        }
    }
}

export { };
