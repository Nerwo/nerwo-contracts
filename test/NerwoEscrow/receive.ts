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

  let platform: SignerWithAddress;
  let client: SignerWithAddress;

  beforeEach(async () => {
    ({ escrow } = await getContracts());
    ({ platform, client } = await getSigners());
  });

  it('check if contract does accepts ethers only from platform', async () => {
    let amount = await randomAmount();
    const address = await escrow.getAddress();

    const tx = platform.sendTransaction({ to: address, value: amount });

    await expect(tx).to.changeEtherBalance(escrow, amount);

    await expect(tx).to.emit(escrow, 'ContractFunded')
      .withArgs(platform.address, amount);

    await expect(client.sendTransaction({ to: address, value: amount }))
      .to.be.reverted;
  });
});
