import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';

import { deployFixture } from './fixtures';

describe('NerwoEscrow: changeFeeRecipient', function () {
  it('Changing fee recipient', async () => {
    const { escrow, platform, sender } = await loadFixture(deployFixture);

    await expect(escrow.connect(platform).changeFeeRecipient(sender.address))
      .to.emit(escrow, 'FeeRecipientChanged')
      .withArgs(platform.address, sender.address);

    await expect(escrow.connect(sender).changeFeeRecipient(platform.address))
      .to.emit(escrow, 'FeeRecipientChanged')
      .withArgs(sender.address, platform.address);
  });

  it('Changing fee recipient: invalid caller', async () => {
    const { escrow, platform, sender } = await loadFixture(deployFixture);

    await expect(escrow.connect(sender).changeFeeRecipient(sender.address))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller').withArgs(platform.address);
  });
});
