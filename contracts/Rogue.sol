// SPDX-License-Identifier: MIT
/**
 *  @authors: [@sherpya]
 */
pragma solidity ^0.8.0;

/* solhint-disable no-console */
import {console} from "hardhat/console.sol";

interface Escrow {
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

    constructor(address _escrow) {
        escrow = Escrow(_escrow);
    }

    fallback() external payable {
        // The fallback function can have the "payable" modifier
        // which means it can accept ether.
        revert("fallback()");
    }

    receive() external payable {
        console.log("Rogue: receive() action %s - transactionID %s - amount %s", uint(action), transactionID, amount);

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
        } else if (action == Action.Revert) {
            console.log("Rogue: reverting");
            revert("Rogue: reverted");
        } else {
            revert("Rogue: invalid action");
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
        console.log("Rogue: payArbitrationFeeBySender %s", amount);
        escrow.payArbitrationFeeBySender{value: amount}(_transactionID);
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
/* solhint-enable no-console */
