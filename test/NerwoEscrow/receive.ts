import { expect } from 'chai';
import { deployments } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

import { NerwoEscrow } from '../../typechain-types';
import { getContracts, getSigners, randomAmount } from '../utils';

describe('NerwoEscrow: receive', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  let escrow: NerwoEscrow;

  let deployer: SignerWithAddress;
  let client: SignerWithAddress;

  beforeEach(async () => {
    ({ escrow } = await getContracts());
    ({ deployer, client } = await getSigners());
  });

  it('check if contract does accepts ethers only from owner', async () => {
    let amount = await randomAmount();
    const address = await escrow.getAddress();

    await expect(deployer.sendTransaction({ to: address, value: amount }))
      .to.changeEtherBalance(escrow, amount)
      .to.emit(escrow, 'ContractFunded').withArgs(deployer.address, amount);

    await expect(client.sendTransaction({ to: address, value: amount }))
      .to.be.reverted;
  });
});
