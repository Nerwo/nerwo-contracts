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

  let deployer: SignerWithAddress;
  let platform: SignerWithAddress;

  beforeEach(async () => {
    ({ escrow } = await getContracts());
    ({ deployer, platform } = await getSigners());
  });

  it('Changing fee recipient', async () => {
    await expect(escrow.connect(deployer).setFeeRecipientAndBasisPoint(platform.address, 550)) // 5.5%
      .to.emit(escrow, 'FeeRecipientChanged')
      .withArgs(platform.address, 550);
  });

  it('Changing fee recipient: Invalid fee basis point', async () => {
    await expect(escrow.connect(deployer).setFeeRecipientAndBasisPoint(platform.address, 5100)) // 51%
      .to.be.revertedWithCustomError(escrow, 'InvalidFeeBasisPoint');
  });
});
