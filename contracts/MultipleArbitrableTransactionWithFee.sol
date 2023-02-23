// SPDX-License-Identifier: MIT
/**
 *  @authors: [@remedcu]
 *  @reviewers: []
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 *  @tools: [MythX]
 */

pragma solidity ^0.4.24;

import {Arbitrator} from "./kleros/Arbitrator.sol";
import {MultipleArbitrableTransaction} from "./kleros/MultipleArbitrableTransaction.sol";

contract MultipleArbitrableTransactionWithFee is MultipleArbitrableTransaction {
    address public feeRecipient; // Address which receives a share of receiver payment.
    uint public feeRecipientBasisPoint; // The share of fee to be received by the feeRecipient, down to 2 decimal places as 550 = 5.5%.

    /** @dev To be emitted when a fee is received by the feeRecipient.
     *  @param _transactionID The index of the transaction.
     *  @param _amount The amount paid.
     */
    event FeeRecipientPayment(uint indexed _transactionID, uint _amount);

    /** @dev To be emitted when a feeRecipient is changed.
     *  @param _oldFeeRecipient Previous feeRecipient.
     *  @param _newFeeRecipient Current feeRecipient.
     */
    event FeeRecipientChanged(address indexed _oldFeeRecipient, address indexed _newFeeRecipient);

    /** @dev Constructor.
     *  @param _arbitrator The arbitrator of the contract.
     *  @param _arbitratorExtraData Extra data for the arbitrator.
     *  @param _feeRecipient Address which receives a share of receiver payment.
     *  @param _feeRecipientBasisPoint The share of fee to be received by the feeRecipient, down to 2 decimal places as 550 = 5.5%.
     *  @param _feeTimeout Arbitration fee timeout for the parties.
     */
    constructor(
        Arbitrator _arbitrator,
        bytes _arbitratorExtraData,
        address _feeRecipient,
        uint _feeRecipientBasisPoint,
        uint _feeTimeout
    ) public MultipleArbitrableTransaction(_arbitrator, _arbitratorExtraData, _feeTimeout) {
        feeRecipient = _feeRecipient;
        // Basis point being set higher than 10000 will result in underflow, but it's the responsibility of the deployer of the contract.
        feeRecipientBasisPoint = _feeRecipientBasisPoint;
    }

    /** @dev Calculate the amount to be paid in wei according to feeRecipientBasisPoint for a particular amount.
     *  @param _amount Amount to pay in wei.
     */
    function calculateFeeRecipientAmount(uint _amount) internal view returns (uint feeAmount) {
        feeAmount = (_amount * feeRecipientBasisPoint) / 10000;
    }

    /** @dev Change Fee Recipient.
     *  @param _newFeeRecipient Address of the new Fee Recipient.
     */
    function changeFeeRecipient(address _newFeeRecipient) public {
        require(msg.sender == feeRecipient, "The caller must be the current Fee Recipient");
        feeRecipient = _newFeeRecipient;

        emit FeeRecipientChanged(msg.sender, _newFeeRecipient);
    }

    /** @dev Pay receiver. To be called if the good or service is provided.
     *  @param _transactionID The index of the transaction.
     *  @param _amount Amount to pay in wei.
     */
    function pay(uint _transactionID, uint _amount) public {
        Transaction storage transaction = transactions[_transactionID];
        require(transaction.sender == msg.sender, "The caller must be the sender.");
        require(transaction.status == Status.NoDispute, "The transaction shouldn't be disputed.");
        require(_amount <= transaction.amount, "The amount paid has to be less than or equal to the transaction.");

        transaction.amount -= _amount;

        uint feeAmount = calculateFeeRecipientAmount(_amount);
        feeRecipient.send(feeAmount);
        transaction.receiver.send(_amount - feeAmount);

        emit Payment(_transactionID, _amount, msg.sender);
        emit FeeRecipientPayment(_transactionID, feeAmount);
    }

    /** @dev Transfer the transaction's amount to the receiver if the timeout has passed.
     *  @param _transactionID The index of the transaction.
     */
    function executeTransaction(uint _transactionID) public {
        Transaction storage transaction = transactions[_transactionID];
        require(now - transaction.lastInteraction >= transaction.timeoutPayment, "The timeout has not passed yet.");
        require(transaction.status == Status.NoDispute, "The transaction shouldn't be disputed.");

        uint amount = transaction.amount;
        transaction.amount = 0;
        uint feeAmount = calculateFeeRecipientAmount(amount);
        feeRecipient.send(feeAmount);
        transaction.receiver.send(amount - feeAmount);

        emit FeeRecipientPayment(_transactionID, feeAmount);

        transaction.status = Status.Resolved;
    }

    /** @dev Execute a ruling of a dispute. It reimburses the fee to the winning party.
     *  @param _transactionID The index of the transaction.
     *  @param _ruling Ruling given by the arbitrator. 1 : Reimburse the receiver. 2 : Pay the sender.
     */
    function executeRuling(uint _transactionID, uint _ruling) internal {
        Transaction storage transaction = transactions[_transactionID];
        require(_ruling <= AMOUNT_OF_CHOICES, "Invalid ruling.");

        uint amount = transaction.amount;
        uint senderArbitrationFee = transaction.senderFee;
        uint receiverArbitrationFee = transaction.receiverFee;

        transaction.amount = 0;
        transaction.senderFee = 0;
        transaction.receiverFee = 0;

        uint feeAmount;

        // Give the arbitration fee back.
        // Note that we use send to prevent a party from blocking the execution.
        if (_ruling == SENDER_WINS) {
            transaction.sender.send(senderArbitrationFee + amount);
        } else if (_ruling == RECEIVER_WINS) {
            feeAmount = calculateFeeRecipientAmount(amount);

            feeRecipient.send(feeAmount);
            transaction.receiver.send(receiverArbitrationFee + amount - feeAmount);

            emit FeeRecipientPayment(_transactionID, feeAmount);
        } else {
            uint split_arbitration = senderArbitrationFee / 2;
            uint split_amount = amount / 2;
            feeAmount = calculateFeeRecipientAmount(split_amount);

            transaction.sender.send(split_arbitration + split_amount);
            feeRecipient.send(feeAmount);
            transaction.receiver.send(split_arbitration + split_amount - feeAmount);

            emit FeeRecipientPayment(_transactionID, feeAmount);
        }

        transaction.status = Status.Resolved;
    }
}
