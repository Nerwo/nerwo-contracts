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
    const { platform, client } = await getSigners();

    await expect(escrow.connect(platform).changeFeeRecipient(client.address))
      .to.emit(escrow, 'FeeRecipientChanged')
      .withArgs(platform.address, client.address);

    await expect(escrow.connect(client).changeFeeRecipient(platform.address))
      .to.emit(escrow, 'FeeRecipientChanged')
      .withArgs(client.address, platform.address);
  });

  it('Changing fee recipient: invalid caller', async () => {
    const { escrow } = await getContracts();
    const { platform, client } = await getSigners();

    await expect(escrow.connect(client).changeFeeRecipient(client.address))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller');
  });
});
