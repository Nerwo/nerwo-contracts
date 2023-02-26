import { ethers, upgrades } from 'hardhat';

async function deployArbitrator() {
    const ARBITRATOR_PRICE = ethers.utils.parseEther(process.env.NERWO_ARBITRATION_PRICE);

    const NerwoCentralizedArbitratorV1 = await ethers.getContractFactory("NerwoCentralizedArbitratorV1");
    const caV1 = await upgrades.deployProxy(NerwoCentralizedArbitratorV1, [ARBITRATOR_PRICE], {
        kind: 'uups',
        initializer: 'initialize',
    });
    caV1.deployed();
    console.log(`NerwoCentralizedArbitratorV1 is deployed to proxy address: ${caV1.address}`);

    let versionAwareContractName = await caV1.getContractNameWithVersion();
    console.log(`NerwoCentralizedArbitratorV1 Version: ${versionAwareContractName}`);

    const NerwoCentralizedArbitratorV2 = await ethers.getContractFactory("NerwoCentralizedArbitratorV1"); // same for now
    const upgraded = await upgrades.upgradeProxy(caV1.address, NerwoCentralizedArbitratorV2, {
        kind: 'uups',
        call: { fn: 'initialize2', args: [ARBITRATOR_PRICE] }
    });
    console.log(`NerwoCentralizedArbitratorV2 is upgraded in proxy address: ${upgraded.address}`);

    versionAwareContractName = await upgraded.versionAwareContractName(); // getContractNameWithVersion()
    console.log(`NerwoCentralizedArbitratorV2 Version: ${versionAwareContractName}`);
    return upgraded.address;
}

async function deployEscrow(arbitrator: string) {
    const ARGS = [
        arbitrator,
        [], // _arbitratorExtraData
        process.env.NERWO_PLATFORM_ADDRESS,
        process.env.NERWO_FEE_RECIPIENT_BASISPOINT,
        process.env.NERWO_FEE_TIMEOUT
    ]

    const NerwoEscrowV1 = await ethers.getContractFactory("NerwoEscrowV1");
    const escrowV1 = await upgrades.deployProxy(NerwoEscrowV1, ARGS, {
        kind: 'uups',
        initializer: 'initialize',
    });
    escrowV1.deployed();
    console.log(`NerwoEscrowV1 is deployed to proxy address: ${escrowV1.address}`);

    let versionAwareContractName = await escrowV1.getContractNameWithVersion();
    console.log(`NerwoCentralizedArbitratorV1 Version: ${versionAwareContractName}`);

    const NerwoEscrowV2 = await ethers.getContractFactory("NerwoEscrowV1"); // same for now
    const upgraded = await upgrades.upgradeProxy(escrowV1.address, NerwoEscrowV2, {
        kind: 'uups',
        call: { fn: 'initialize2', args: ARGS }
    });
    console.log(`NerwoEscrowV2 is upgraded in proxy address: ${upgraded.address}`);

    versionAwareContractName = await upgraded.versionAwareContractName(); // getContractNameWithVersion()
    console.log(`NerwoEscrowV2 Version: ${versionAwareContractName}`);
}

async function main() {
    const arbtitrator = await deployArbitrator();
    await deployEscrow(arbtitrator);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
