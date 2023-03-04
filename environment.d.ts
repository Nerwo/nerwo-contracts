declare global {
    namespace NodeJS {
        interface ProcessEnv {
            PRIVATE_KEY: string;
            NERWO_COURT_ADDRESS: string;
            NERWO_PLATFORM_ADDRESS: string;
            NERWO_ARBITRATION_PRICE: string;
            NERWO_MINIMAL_AMOUNT: string;
            NERWO_FEE_TIMEOUT: number;
            NERWO_FEE_PRICE_THRESHOLDS: string;
        }
    }
}

export { };
