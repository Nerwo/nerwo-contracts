import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { NerwoEscrowV1 } from '../typechain-types';

describe('NerwoEscrow: changeFeeRecipient', function () {
  let escrow: NerwoEscrowV1;
  let deployer: SignerWithAddress, platform: SignerWithAddress;
  let sender: SignerWithAddress, receiver: SignerWithAddress;

  this.beforeEach(async () => {
    [deployer, platform, , sender, receiver] = await ethers.getSigners();

    await deployments.fixture(['NerwoCentralizedArbitratorV1', 'NerwoEscrowV1'], {
      keepExistingDeployments: true
    });

    let deployment = await deployments.get('NerwoEscrowV1');
    escrow = await ethers.getContractAt('NerwoEscrowV1', deployment.address);
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
