import { ethers, upgrades } from 'hardhat';

async function main() {
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
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
