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
    const amount = ethers.utils.parseEther('0.001');

    await expect(escrow.connect(sender).createTransaction(
      constants.TIMEOUT_PAYMENT,
      constants.ZERO_ADDRESS,
      '',
      { value: amount })).to.be.revertedWithCustomError(escrow, 'NullAddress');

  });

  // TODO: minimum amount
  // TODO: pass _timeoutPayment > uint64
});
