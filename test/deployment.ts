import { ethers } from 'hardhat';

import { arbitratorArgs, escrowArgs } from '../constructors';

(process.env.REPORT_GAS ? describe : describe.skip)('Deployment: for gas calculation', function () {
    it('NerwoCentralizedArbitrator', async () => {
        const [deployer] = await ethers.getSigners();
        const NerwoCentralizedArbitrator = await ethers.getContractFactory('NerwoCentralizedArbitrator');
        const args = arbitratorArgs(deployer.address);
        const arbitrator = await NerwoCentralizedArbitrator.deploy(...args);
        await arbitrator.deployed();
    });

    it('NerwoEscrow', async () => {
        const [deployer] = await ethers.getSigners();
        const NerwoEscrow = await ethers.getContractFactory('NerwoEscrow');
        const args = escrowArgs(deployer.address, deployer.address, deployer.address, deployer.address);
        const escrow = await NerwoEscrow.deploy(...args);
        await escrow.deployed();
    });
});
