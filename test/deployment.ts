import { ethers } from 'hardhat';

import { arbitratorArgs, escrowArgs } from '../constructors';
import { NerwoCentralizedArbitrator, NerwoEscrow } from '../typechain-types';

(process.env.REPORT_GAS ? describe : describe.skip)('Deployment: for gas calculation', function () {
    it('NerwoCentralizedArbitrator', async () => {
        const [deployer] = await ethers.getSigners();
        const NerwoCentralizedArbitrator = await ethers.getContractFactory('NerwoCentralizedArbitrator');
        const arbitrator: NerwoCentralizedArbitrator = await NerwoCentralizedArbitrator.deploy() as NerwoCentralizedArbitrator;
        await arbitrator.waitForDeployment();
        const args = arbitratorArgs(deployer.address, deployer.address) as [string, string[], string];
        await arbitrator.initialize(...args);
    });

    it('NerwoEscrow', async () => {
        const [deployer] = await ethers.getSigners();
        const NerwoEscrow = await ethers.getContractFactory('NerwoEscrow');
        const escrow: NerwoEscrow = await NerwoEscrow.deploy() as NerwoEscrow;
        await escrow.waitForDeployment();
        const args = escrowArgs(deployer.address, deployer.address, deployer.address) as [
            string, string, string, string, string, string, string, any[] // wft
        ];
        await escrow.initialize(...args);
    });
});
