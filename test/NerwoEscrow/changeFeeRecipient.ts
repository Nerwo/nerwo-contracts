import { expect } from 'chai';
import { deployments } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

import { NerwoEscrow } from '../../typechain-types';
import { getContracts, getSigners } from '../utils';

describe('NerwoEscrow: changeFeeRecipient', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  let escrow: NerwoEscrow;

  let deployer: SignerWithAddress;
  let platform: SignerWithAddress;
  let client: SignerWithAddress;

  beforeEach(async () => {
    ({ escrow } = await getContracts());
    ({ deployer, platform, client } = await getSigners());
  });

  it('Changing fee recipient', async () => {
    await expect(escrow.connect(deployer).changeFeeRecipient(platform.address))
      .to.emit(escrow, 'FeeRecipientChanged')
      .withArgs(deployer.address, platform.address);
  });

  it('Changing fee recipient: Ownable: caller is not the owner', async () => {
    await expect(escrow.connect(platform).changeFeeRecipient(client.address))
      .to.be.reverted;
  });
});
