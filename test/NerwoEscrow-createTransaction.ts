import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { NerwoEscrowV1 } from '../typechain-types';

import * as constants from '../constants';

describe('NerwoEscrow: createTransaction', function () {
  let escrow: NerwoEscrowV1;
  let deployer: SignerWithAddress, sender: SignerWithAddress;

  this.beforeEach(async () => {
    [deployer, , , sender] = await ethers.getSigners();

    process.env.NERWO_COURT_ADDRESS = deployer.address;
    await deployments.fixture(['NerwoCentralizedArbitratorV1', 'NerwoEscrowV1']);

    let deployment = await deployments.get('NerwoEscrowV1');
    escrow = await ethers.getContractAt('NerwoEscrowV1', deployment.address);
  });

  it('Creating transaction with null receiver', async () => {
    const amount = await escrow.minimalAmount();
    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT,
      constants.ZERO_ADDRESS,
      '',
      { value: amount })).to.be.revertedWithCustomError(escrow, 'NullAddress');
  });

  it('Creating transaction < minimalAmount', async () => {
    const minimalAmount = await escrow.minimalAmount();
    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT,
      sender.address,
      '',
      { value: minimalAmount.sub(1) }))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount').withArgs(minimalAmount);
  });

  it('Creating transaction with overflowing _timeoutPayment', async () => {
    const amount = await escrow.minimalAmount();
    const timeoutPayment = ethers.BigNumber.from(2).pow(32);

    await expect(escrow.connect(sender).createTransaction(
      timeoutPayment,
      sender.address,
      '',
      { value: amount }))
      .to.be.revertedWith(`SafeCast: value doesn't fit in 32 bits`);
  });
});
