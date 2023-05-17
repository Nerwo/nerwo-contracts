import { expect } from 'chai';
import { deployments } from 'hardhat';

import { IArbitrable__factory, IArbitrator__factory, IERC165__factory } from '../typechain-types';

import { getContracts, getInterfaceID } from './utils';

describe('supportsInterface', function () {
  before(async () => {
    await deployments.fixture(['NerwoEscrow', 'NerwoCentralizedArbitrator'], {
      keepExistingDeployments: true
    });
  });

  it('NerwoEscrow', async () => {
    const { escrow } = await getContracts();
    const IERC165 = IERC165__factory.createInterface();
    const IArbitrable = IArbitrable__factory.createInterface();
    expect(await escrow.supportsInterface(getInterfaceID(IERC165))).to.be.true;
    expect(await escrow.supportsInterface(getInterfaceID(IArbitrable))).to.be.true;
  });

  it('NerwoCentralizedArbitrator', async () => {
    const { arbitrator } = await getContracts();
    const IERC165 = IERC165__factory.createInterface();
    const IArbitrator = IArbitrator__factory.createInterface();
    expect(await arbitrator.supportsInterface(getInterfaceID(IERC165))).to.be.true;
    expect(await arbitrator.supportsInterface(getInterfaceID(IArbitrator))).to.be.true;
  });
});
