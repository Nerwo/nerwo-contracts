import { expect } from 'chai';
import { deployments } from 'hardhat';

import { getContracts, getSigners, createTransaction, randomAmount, createNativeTransaction, NativeToken } from '../utils';

describe('NerwoEscrow: reimburse', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoTetherToken'], {
      keepExistingDeployments: true
    });
  });

  it('reimbursing a transaction (ERC20)', async () => {
    const { escrow, usdt } = await getContracts();
    const { client, freelancer } = await getSigners();

    const amount = await randomAmount();
    const transactionID = await createTransaction(client, freelancer.address, usdt, amount);

    const usdtAddress = await usdt.getAddress();

    let tx = escrow.connect(freelancer).reimburse(transactionID);

    await expect(tx).to.changeTokenBalances(
      usdt,
      [escrow, client, freelancer],
      [-amount, amount, 0]
    );

    await expect(tx).to.emit(escrow, 'Reimburse')
      .withArgs(transactionID, freelancer.address, client.address, usdtAddress, amount);

    await expect(escrow.connect(freelancer).reimburse(transactionID))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');
  });

  it('reimbursing a transaction (Native)', async () => {
    const { escrow } = await getContracts();
    const { client, freelancer } = await getSigners();

    const amount = await randomAmount();
    const transactionID = await createNativeTransaction(client, freelancer.address, amount);

    const tx = escrow.connect(freelancer).reimburse(transactionID);

    await expect(tx).to.changeEtherBalances(
      [escrow, client, freelancer],
      [-amount, amount, 0]
    );

    await expect(tx).to.emit(escrow, 'Reimburse')
      .withArgs(transactionID, freelancer.address, client.address, NativeToken, amount);

    await expect(escrow.connect(freelancer).reimburse(transactionID))
      .to.be.revertedWithCustomError(escrow, 'InvalidAmount');
  });
});
