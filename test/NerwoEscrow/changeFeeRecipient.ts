import { expect } from 'chai';
import { deployments } from 'hardhat';
import { getContracts, getSigners } from '../utils';

describe('NerwoEscrow: changeFeeRecipient', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('Changing fee recipient', async () => {
    const { escrow } = await getContracts();
    const { platform, sender } = await getSigners();

    await expect(escrow.connect(platform).changeFeeRecipient(sender.address))
      .to.emit(escrow, 'FeeRecipientChanged')
      .withArgs(platform.address, sender.address);

    await expect(escrow.connect(sender).changeFeeRecipient(platform.address))
      .to.emit(escrow, 'FeeRecipientChanged')
      .withArgs(sender.address, platform.address);
  });

  it('Changing fee recipient: invalid caller', async () => {
    const { escrow } = await getContracts();
    const { platform, sender } = await getSigners();

    await expect(escrow.connect(sender).changeFeeRecipient(sender.address))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller').withArgs(platform.address);
  });
});
