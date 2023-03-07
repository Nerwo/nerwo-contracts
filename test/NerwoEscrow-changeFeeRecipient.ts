import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { NerwoEscrow } from '../typechain-types';

describe('NerwoEscrow: changeFeeRecipient', function () {
  let escrow: NerwoEscrow;
  let deployer: SignerWithAddress, platform: SignerWithAddress;
  let sender: SignerWithAddress, receiver: SignerWithAddress;

  this.beforeEach(async () => {
    [deployer, platform, , sender, receiver] = await ethers.getSigners();

    await deployments.fixture(['NerwoCentralizedArbitrator', 'NerwoEscrow'], {
      keepExistingDeployments: true
    });

    let deployment = await deployments.get('NerwoEscrow');
    escrow = await ethers.getContractAt('NerwoEscrow', deployment.address);
  });

  it('Changing fee recipient', async () => {
    await expect(escrow.connect(platform).changeFeeRecipient(sender.address))
      .to.emit(escrow, 'FeeRecipientChanged')
      .withArgs(platform.address, sender.address);

    await expect(escrow.connect(sender).changeFeeRecipient(platform.address))
      .to.emit(escrow, 'FeeRecipientChanged')
      .withArgs(sender.address, platform.address);
  });

  it('Changing fee recipient: invalid caller', async () => {
    await expect(escrow.connect(sender).changeFeeRecipient(sender.address))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller').withArgs(platform.address);
  });
});
