export interface Token {
    name: string;
    ticker: string;
    symbolURI: string;
    address?: any;
    decimals: number;
}

export interface RulingOptions {
    type?: 'single-select';
    titles: string[];
    descriptions: string[];
}

export interface MetaEvidence {
    title: string;
    description: string;
    category: string;
    subCategory: string;
    question: string;
    rulingOptions: RulingOptions;
    token: Token;

    sender: string;
    receiver: string;
    amount: string;

    aliases: Map<string, string>;
    arbitrableAddress: string;

    timeout: number;
    invoice: boolean;

    extraData?: any;

    fileURI: string;
    fileHash: string;
    fileTypeExtension: string;

    evidenceDisplayInterfaceURI: string; /* evidenceDisplayInterfaceURL */
    evidenceDisplayInterfaceHash: string; /* evidenceDisplayInterfaceURLHash */
    selfHash: string;
}
