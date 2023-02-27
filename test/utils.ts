import { expect } from 'chai';
import { ContractTransaction, Event } from '@ethersproject/contracts';

export async function findEventByName(txResponse: ContractTransaction, name: string): Promise<Event> {
  const txReceipt = await txResponse.wait();

  expect(txReceipt.events).to.be.an('array').that.is.not.empty;

  const event = txReceipt.events!.find(event => event.event === name);
  expect(event).to.not.be.undefined;

  return event!;
}
