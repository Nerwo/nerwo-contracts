import { expect } from 'chai';
import { deployments } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

import { NerwoEscrow } from '../../typechain-types';
import { getContracts, getSigners } from '../utils';

describe('NerwoEscrow: setFeeRecipientAndBasisPoint', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  let escrow: NerwoEscrow;

  let platform: SignerWithAddress;

  beforeEach(async () => {
    ({ escrow } = await getContracts());
    ({ platform } = await getSigners());
  });

  it('Changing fee recipient', async () => {
    await expect(escrow.connect(platform).setFeeRecipientAndBasisPoint(platform.address, 2000)) // < MAX
      .to.emit(escrow, 'FeeRecipientChanged')
      .withArgs(platform.address, 2000);
  });

  it('Changing fee recipient: Invalid fee basis point', async () => {
    await expect(escrow.connect(platform).setFeeRecipientAndBasisPoint(platform.address, 2001)) // > MAX
      .to.be.revertedWithCustomError(escrow, 'InvalidFeeBasisPoint');
  });
});
