// SPDX-License-Identifier: MIT
/**
 *  @authors: [@sherpya]
 */
pragma solidity ^0.8.0;

/* solhint-disable no-console */
import {console} from "hardhat/console.sol";

interface Escrow {
    function createTransaction(
        uint256 _timeoutPayment,
        address _receiver,
        string calldata _metaEvidence
    ) external payable returns (uint256 transactionID);

    function pay(uint256 _transactionID, uint256 _amount) external;

    function payArbitrationFeeBySender(uint256 _transactionID) external payable;
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
    uint256 public transactionID = 0;
    uint256 public amount = 0;

    event TransactionCreated(uint256 _transactionID, address indexed _sender, address indexed _receiver, uint256 _amount);

    constructor(address _escrow) {
        escrow = Escrow(_escrow);
    }

    fallback() external payable {
        // The fallback function can have the "payable" modifier
        // which means it can accept ether.
        revert("fallback()");
    }

    receive() external payable {
        console.log("Rogue: receive() action %s - transactionID %s - amount %s", uint256(action), transactionID, amount);

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

    function setAction(uint256 _action) external {
        Action newAction = Action(_action);
        require(newAction <= Action.Revert, "Invalid action");
        action = newAction;
    }

    function setTransaction(uint256 _transactionID) external {
        transactionID = _transactionID;
    }

    function setAmount(uint256 _amount) external {
        amount = _amount;
    }

    function transferTo(address _to, uint256 _amount) external payable {
        require(address(this).balance >= amount, "Not enough funds");
        payable(_to).transfer(_amount);
    }

    function createTransaction(
        uint256 _timeoutPayment,
        address _receiver,
        string calldata _metaEvidence
    ) external payable returns (uint256 _transactionID) {
        _transactionID = escrow.createTransaction{value: amount}(_timeoutPayment, _receiver, _metaEvidence);
        emit TransactionCreated(_transactionID, msg.sender, _receiver, amount);
    }

    function payArbitrationFeeBySender(uint256 _transactionID) external payable {
        console.log("Rogue: payArbitrationFeeBySender %s", amount);
        escrow.payArbitrationFeeBySender{value: amount}(_transactionID);
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
/* solhint-enable no-console */
