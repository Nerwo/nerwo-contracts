import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';

import { getContracts, getSigners, createTransaction, randomAmount } from '../utils';

describe('NerwoEscrow: submitEvidence', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'TetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('submitting evidences', async () => {
    const { escrow, usdt } = await getContracts();
    const { court, sender, receiver } = await getSigners();

    const amount = await randomAmount();
    const transactionID = await createTransaction(sender, receiver.address, usdt, amount);

    await expect(escrow.connect(court).submitEvidence(transactionID, 'invalid'))
      .to.revertedWithCustomError(escrow, 'InvalidCaller');

    await expect(escrow.connect(sender).submitEvidence(0, 'invalid transactionID'))
      .to.revertedWithCustomError(escrow, 'InvalidCaller');

    const arbitrator = await escrow.arbitrator();

    await expect(escrow.connect(sender).submitEvidence(transactionID, 'sender evidence'))
      .to.emit(escrow, 'Evidence').withArgs(arbitrator, transactionID, sender.address, 'sender evidence');

    await expect(escrow.connect(receiver).submitEvidence(transactionID, 'receiver evidence'))
      .to.emit(escrow, 'Evidence').withArgs(arbitrator, transactionID, receiver.address, 'receiver evidence');
  });
});
