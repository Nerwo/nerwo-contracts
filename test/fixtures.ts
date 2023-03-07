import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';

export async function deployFixture() {
    await deployments.fixture(['NerwoCentralizedArbitrator', 'NerwoEscrow'], {
        keepExistingDeployments: true
    });

    let deployment = await deployments.get('NerwoEscrow');
    const escrow = await ethers.getContractAt('NerwoEscrow', deployment.address);

    deployment = await deployments.get('NerwoCentralizedArbitrator');
    const arbitrator = await ethers.getContractAt('NerwoCentralizedArbitrator', deployment.address);

    const Rogue = await ethers.getContractFactory("Rogue");
    const rogue = await Rogue.deploy(escrow.address);
    await rogue.deployed();

    const [deployer, platform, court, sender, receiver] = await ethers.getSigners();

    return {
        arbitrator, escrow, rogue,
        deployer, platform, court, sender, receiver
    };
}

export async function deployAndFundRogueFixture() {
    const fixture = await loadFixture(deployFixture);
    const rogueFunds = ethers.utils.parseEther('10.0');
    await expect(fixture.sender.sendTransaction({ to: fixture.rogue.address, value: rogueFunds }))
        .to.changeEtherBalance(fixture.rogue, rogueFunds);
    return fixture;
}
