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

    process.env.NERWO_COURT_ADDRESS = deployer.address;
    await deployments.fixture(['NerwoCentralizedArbitratorV1', 'NerwoEscrowV1']);

    let deployment = await deployments.get('NerwoEscrowV1');
    escrow = await ethers.getContractAt('NerwoEscrowV1', deployment.address);
  });

  it('Changing fee recipient', async () => {
    await expect(escrow.connect(platform).changeFeeRecipient(sender.address))
      .to.emit(escrow, 'FeeRecipientChanged')
      .withArgs(platform.address, sender.address);
  });

  it('Changing fee recipient: invalid caller', async () => {
    await expect(escrow.connect(sender).changeFeeRecipient(sender.address))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller').withArgs(platform.address);
  });
});
