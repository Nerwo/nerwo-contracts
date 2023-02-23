declare global {
    namespace NodeJS {
        interface ProcessEnv {
            RPC_URL: string;
            PRIVATE_KEY: string;
            ETHERSCAN_API_KEY: string;
            NERWO_COURT_ADDRESS: string;
            NERWO_PLATFORM_ADDRESS: string;
            NERWO_ARBITRATION_PRICE: string;
            NERWO_FEE_TIMEOUT: number;
            NERWO_FEE_RECIPIENT_BASISPOINT: number;
        }
    }
}

export { };
