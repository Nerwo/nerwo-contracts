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

  let platform: SignerWithAddress;
  let client: SignerWithAddress;

  beforeEach(async () => {
    ({ escrow } = await getContracts());
    ({ platform, client } = await getSigners());
  });

  it('Changing fee recipient', async () => {
    await expect(escrow.connect(platform).changeFeeRecipient(client.address))
      .to.emit(escrow, 'FeeRecipientChanged')
      .withArgs(platform.address, client.address);

    await expect(escrow.connect(client).changeFeeRecipient(platform.address))
      .to.emit(escrow, 'FeeRecipientChanged')
      .withArgs(client.address, platform.address);
  });

  it('Changing fee recipient: invalid caller', async () => {
    await expect(escrow.connect(client).changeFeeRecipient(client.address))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller');
  });
});
