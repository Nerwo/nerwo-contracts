import { ethers } from 'hardhat';

import * as constants from '../constants';

(process.env.REPORT_GAS ? describe : describe.skip)('Deployment: for gas calculation', function () {
    it('NerwoCentralizedArbitrator', async () => {
        const [deployer] = await ethers.getSigners();
        const NerwoCentralizedArbitrator = await ethers.getContractFactory('NerwoCentralizedArbitrator');
        const arbitrator = await NerwoCentralizedArbitrator.deploy(
            deployer.address, constants.ARBITRATOR_PRICE);
        await arbitrator.deployed();
    });

    it('NerwoEscrow', async () => {
        const [deployer] = await ethers.getSigners();
        const NerwoEscrow = await ethers.getContractFactory('NerwoEscrow');
        const escrow = await NerwoEscrow.deploy(
            deployer.address,                       /* _owner */
            deployer.address,                       /* _arbitrator */
            [],                                     /* _arbitratorExtraData */
            constants.FEE_TIMEOUT,                  /* _feeTimeout */
            constants.MINIMAL_AMOUNT,               /* _minimalAmount */
            deployer.address,                       /* _feeRecipient */
            constants.FEE_RECIPIENT_BASISPOINT,     /* _feeRecipientBasisPoint */
            [deployer.address, deployer.address],   /* _tokensWhitelist */
        );
        await escrow.deployed();
    });
});
