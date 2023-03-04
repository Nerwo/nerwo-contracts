import { expect } from 'chai';
import { deployments, ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { NerwoEscrowV1 } from '../typechain-types';

import * as constants from '../constants';

describe('NerwoEscrow: setPriceThresholds', function () {
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

  it('Testing priceThresholds', async () => {
    const answer = ethers.BigNumber.from(42);
    const priceThreshold = {
      maxPrice: answer,
      feeBasisPoint: '0'
    };

    expect(constants.FEE_PRICE_THRESHOLDS).to.be.an('array').that.lengthOf.at.least(2);

    expect((await escrow.priceThresholds(1)).maxPrice)
      .to.be.equal(constants.FEE_PRICE_THRESHOLDS[1].maxPrice);

    await escrow.connect(deployer).setPriceThresholds([priceThreshold]);
    expect((await escrow.priceThresholds(0)).maxPrice).to.be.equal(answer);

    await expect(escrow.priceThresholds(1))
      .to.be.revertedWithoutReason();

    // reset back to original
    await escrow.connect(deployer).setPriceThresholds(constants.FEE_PRICE_THRESHOLDS);

    for (const priceThreshold of constants.FEE_PRICE_THRESHOLDS) {
      const amount = priceThreshold.maxPrice;
      const feeAmount = amount.mul(priceThreshold.feeBasisPoint).div(10000);
      expect(await escrow.calculateFeeRecipientAmount(amount)).to.be.equal(feeAmount);
    }
  });
});
