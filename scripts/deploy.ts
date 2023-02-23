import { ethers } from 'hardhat';

async function main() {
  const ARBITRATOR_PRICE = ethers.utils.parseEther(process.env.NERWO_ARBITRATION_PRICE);

  console.log('Deploying CentralizedArbitrator Contract...');
  const CentralizedArbitratorFactory = await ethers.getContractFactory('CentralizedArbitrator');
  const arbitrator = await CentralizedArbitratorFactory.deploy(ARBITRATOR_PRICE);
  await arbitrator.deployed();
  await arbitrator.transferOwnership(process.env.NERWO_COURT_ADDRESS);
  console.log(`CentralizedArbitrator Contract deployed at: ${arbitrator.address}`);

  console.log('Deploying MultipleArbitrableTransactionWithFee Contract...');
  const MultipleArbitrableTransactionWithFeeFactory = await ethers.getContractFactory('MultipleArbitrableTransactionWithFee');
  const escrowContract = await MultipleArbitrableTransactionWithFeeFactory.deploy(
    arbitrator.address,
    [], // _arbitratorExtraData
    process.env.NERWO_PLATFORM_ADDRESS,
    process.env.NERWO_FEE_RECIPIENT_BASISPOINT,
    process.env.NERWO_FEE_TIMEOUT);
  await escrowContract.deployed();
  console.log(`MultipleArbitrableTransactionWithFee deployed at: ${escrowContract.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
