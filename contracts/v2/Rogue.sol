// SPDX-License-Identifier: MIT
/**
 *  @authors: [@sherpya]
 */
pragma solidity ^0.8;

import "hardhat/console.sol";

enum Status {
    NoDispute,
    WaitingSender,
    WaitingReceiver,
    DisputeCreated,
    Resolved
}

struct Transaction {
    address payable sender;
    address payable receiver;
    uint amount;
    uint timeoutPayment; // Time in seconds after which the transaction can be automatically executed if not disputed.
    uint disputeId; // If dispute exists, the ID of the dispute.
    uint senderFee; // Total fees paid by the sender.
    uint receiverFee; // Total fees paid by the receiver.
    uint lastInteraction; // Last interaction for the dispute procedure.
    Status status;
}

interface Escrow {
    function transactions(uint _transactionID) external returns (Transaction calldata transaction);

    function createTransaction(
        uint _timeoutPayment,
        address _receiver,
        string calldata _metaEvidence
    ) external payable returns (uint transactionID);

    function pay(uint _transactionID, uint _amount) external;

    function payArbitrationFeeBySender(uint _transactionID) external payable;
}

contract Rogue {
    enum Action {
        None,
        Pay,
        PayArbitrationFeeBySender,
        Revert
    }

    Escrow public immutable escrow;

    Action public action = Action.None;
    uint public transactionID = 0;
    uint public amount = 0;

    event TransactionCreated(uint _transactionID, address indexed _sender, address indexed _receiver, uint _amount);
    event Dispute(address indexed _arbitrator, uint indexed _disputeID, uint _metaEvidenceID, uint _evidenceGroupID);

    constructor(address _escrow) {
        escrow = Escrow(_escrow);
    }

    fallback() external payable {
        // The fallback function can have the "payable" modifier
        // which means it can accept ether.
        revert();
    }

    receive() external payable {
        console.log(
            "Rogue: receive() action %s - transactionID %s - amount %s",
            uint(action),
            transactionID,
            amount
        );

        Escrow caller = Escrow(msg.sender);

        if (action == Action.None) {
            console.log("Rogue: receive() Received %s", msg.value);
        } else if (action == Action.Pay) {
            console.log("Rogue: receive() Calling pay(%s, %s)", transactionID, amount);
            caller.pay(transactionID, amount);
            console.log("Rogue: receive() Called pay()");
        } else if (action == Action.PayArbitrationFeeBySender) {
            console.log("Rogue: receive() calling payArbitrationFeeBySender pay(%s, %s)", transactionID, amount);
            caller.payArbitrationFeeBySender{value: amount}(transactionID);
            console.log("Rogue: receive() called payArbitrationFeeBySender()");
        } else {
            revert();
        }
    }

    function setAction(uint _action) external {
        Action newAction = Action(_action);
        require(newAction <= Action.Revert, "Invalid action");
        action = newAction;
    }

    function setTransaction(uint _transactionID) external {
        transactionID = _transactionID;
    }

    function setAmount(uint _amount) external {
        amount = _amount;
    }

    function transferTo(address _to, uint _amount) external payable {
        require(address(this).balance >= amount, "Not enough funds");
        payable(_to).transfer(_amount);
    }

    function createTransaction(
        uint _timeoutPayment,
        address _receiver,
        string calldata _metaEvidence
    ) external payable returns (uint _transactionID) {
        _transactionID = escrow.createTransaction{value: amount}(_timeoutPayment, _receiver, _metaEvidence);
        emit TransactionCreated(_transactionID, msg.sender, _receiver, amount);
    }

    function payArbitrationFeeBySender(uint _transactionID) external payable {
        Transaction memory transaction = escrow.transactions(_transactionID);
        require(transaction.sender == address(this), "I'm not the transaction sender");

        console.log("Rogue: payArbitrationFeeBySender %s", amount);

        escrow.payArbitrationFeeBySender{value: amount}(_transactionID);

        emit Dispute(address(0), transaction.disputeId, 0, 0);
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
