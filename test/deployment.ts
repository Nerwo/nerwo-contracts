import { ethers } from 'hardhat';

import { arbitratorArgs, escrowArgs } from '../constructors';

(process.env.REPORT_GAS ? describe : describe.skip)('Deployment: for gas calculation', function () {
    it('NerwoCentralizedArbitrator', async () => {
        const [deployer] = await ethers.getSigners();
        const args = arbitratorArgs(deployer.address) as [string, bigint];
        const arbitrator = await ethers.deployContract(
            'NerwoCentralizedArbitrator',
            args);
        await arbitrator.waitForDeployment();
    });

    it('NerwoEscrow', async () => {
        const [deployer] = await ethers.getSigners();
        const args = escrowArgs(deployer.address, deployer.address, deployer.address) as [
            string, string[], string, string, string, any[] // wft
        ];
        const escrow = await ethers.deployContract('NerwoEscrow', args);
        await escrow.waitForDeployment();
    });
});
