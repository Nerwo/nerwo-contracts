import { expect } from 'chai';
import { deployments } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

import { NerwoEscrow, NerwoTetherToken } from '../../typechain-types';
import { getContracts, getSigners, createTransaction, randomAmount, createNativeTransaction, NativeToken } from '../utils';

describe('NerwoEscrow: createTransaction', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  let escrow: NerwoEscrow;
  let usdt: NerwoTetherToken;

  let client: SignerWithAddress;
  let freelancer: SignerWithAddress;

  beforeEach(async () => {
    ({ escrow, usdt } = await getContracts());
    ({ client, freelancer } = await getSigners());
  });

  it('Creating a simple transaction', async () => {
    const amount = await randomAmount();
    await createTransaction(client, freelancer.address, usdt, amount);
  });

  it('Creating a transaction with native token', async () => {
    const amount = await randomAmount();
    await createNativeTransaction(client, freelancer.address, amount);
  });

  it('Creating a transaction with badly mixed arguments', async () => {
    const amount = await randomAmount();

    await expect(escrow.connect(client).createTransaction(usdt, amount, freelancer.address,
      { value: amount }))
      .to.revertedWithCustomError(escrow, 'InvalidToken');
  });

  it('Creating a transaction with myself', async () => {
    const amount = await randomAmount();
    await expect(createTransaction(client, client.address, usdt, amount))
      .to.be.revertedWithCustomError(escrow, 'InvalidCaller');
  });

  it('Creating a transaction with null freelancer', async () => {
    const amount = await randomAmount();
    await expect(createTransaction(client, NativeToken, usdt, amount))
      .to.be.revertedWithCustomError(escrow, 'NullAddress');
  });

  it('Creating a transaction with invalid amount', async () => {
    await expect(createTransaction(client, freelancer.address, usdt, 9999n))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');
  });

  it('Creating a transaction with insufficient allowance', async () => {
    const amount = await randomAmount();
    await expect(createTransaction(client, freelancer.address, usdt, amount, false))
      .to.be.revertedWithCustomError(usdt, 'ERC20InsufficientAllowance');
  });

  it('InvalidToken', async () => {
    const amount = await randomAmount();
    await expect(escrow.connect(client).createTransaction(await escrow.getAddress(), amount, freelancer.address))
      .to.be.revertedWithCustomError(escrow, 'InvalidToken');
  });
});
