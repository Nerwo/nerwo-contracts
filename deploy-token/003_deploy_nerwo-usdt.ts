import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function ({ deployments: { deploy }, getNamedAccounts }) {
    const { deployer } = await getNamedAccounts();

    await deploy('NerwoTetherToken', {
        from: deployer,
        log: true
    })
}

export default func;
func.tags = ['NerwoTetherToken'];
