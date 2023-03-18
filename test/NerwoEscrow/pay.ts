import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';

import * as constants from '../../constants';
import { getContracts, getSigners, fund, createTransaction } from '../utils';

describe('NerwoEscrow: pay', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'Rogue'], {
      keepExistingDeployments: true
    });
  });

  it('rogue as recipient', async () => {
    const { escrow, rogue } = await getContracts();
    const { platform, sender } = await getSigners();

    await fund(rogue, ethers.utils.parseEther('999.0'));

    let amount = ethers.utils.parseEther('0.02');
    const _transactionID = await createTransaction(sender, rogue.address, amount);

    await expect(escrow.connect(sender).pay(_transactionID, 0))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    await expect(escrow.connect(sender).pay(_transactionID, amount.mul(2)))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(amount);

    const feeAmount = await escrow.calculateFeeRecipientAmount(amount);

    await rogue.setAmount(amount.div(2));

    // FIXME: emit order in sol
    // FIXME: make SendFailed and Payment mutually exclusive?
    await rogue.setAction(constants.RogueAction.Pay);
    await expect(escrow.connect(sender).pay(_transactionID, amount))
      .to.changeEtherBalances(
        [escrow, platform, rogue],
        [feeAmount.mul(-1), feeAmount, 0]
      )
      .to.emit(escrow, 'SendFailed').withArgs(rogue.address, amount.sub(feeAmount), anyValue)
      .to.emit(escrow, 'Payment').withArgs(_transactionID, amount, sender.address)
      .to.emit(escrow, 'FeeRecipientPayment');
    await rogue.setAction(constants.RogueAction.None);
  });
});
