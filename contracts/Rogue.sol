// SPDX-License-Identifier: MIT
/**
 *  @authors: [@sherpya]
 */
pragma solidity ^0.8.0;

/* solhint-disable no-console */
import {console} from "hardhat/console.sol";

interface IEscrow {
    function createTransaction(
        uint256 _timeoutPayment,
        address _receiver,
        string calldata _metaEvidence
    ) external payable returns (uint256 transactionID);

    function pay(uint256 _transactionID, uint256 _amount) external;

    function reimburse(uint256 _transactionID, uint256 _amountReimbursed) external;

    function executeTransaction(uint256 _transactionID) external;

    function payArbitrationFeeBySender(uint256 _transactionID) external payable;
}

contract Rogue {
    enum Action {
        None,
        Pay,
        Reimburse,
        ExecuteTransaction,
        PayArbitrationFeeBySender,
        Revert
    }

    event ErrorNotHandled(string reason);

    function strAction(Action _action) internal pure returns (string memory) {
        if (_action == Action.None) {
            return "None";
        } else if (_action == Action.Pay) {
            return "Pay";
        } else if (_action == Action.Reimburse) {
            return "Reimburse";
        } else if (_action == Action.ExecuteTransaction) {
            return "ExecuteTransaction";
        } else if (_action == Action.PayArbitrationFeeBySender) {
            return "PayArbitrationFeeBySender";
        } else if (_action == Action.Revert) {
            return "Revert";
        }
        return "unknown";
    }

    IEscrow public immutable escrow;

    Action public action = Action.None;
    bool public failOnError = true;
    uint256 public transactionID;
    uint256 public amount;

    uint256 public owner = 0x31337;

    event TransactionCreated(
        uint256 _transactionID,
        address indexed _sender,
        address indexed _receiver,
        uint256 _amount
    );

    constructor(address _escrow) {
        escrow = IEscrow(_escrow);
    }

    fallback() external payable {
        // The fallback function can have the "payable" modifier
        // which means it can accept ether.
        revert("fallback()");
    }

    receive() external payable {
        console.log(
            "Rogue: receive() action %s - transactionID %s - amount %s",
            strAction(action),
            transactionID,
            amount
        );

        IEscrow caller = IEscrow(msg.sender);
        string memory reason;

        if (action == Action.None) {
            console.log("Rogue: receive() Received %s", msg.value);
        } else if (action == Action.Pay) {
            console.log("Rogue: receive() Calling pay(%s, %s)", transactionID, amount);
            try caller.pay(transactionID, amount) {} catch Error(string memory _reason) {
                reason = _reason;
            }
        } else if (action == Action.ExecuteTransaction) {
            console.log("Rogue: receive() calling executeTransaction(%s)", transactionID);
            try caller.executeTransaction(transactionID) {} catch Error(string memory _reason) {
                reason = _reason;
            }
        } else if (action == Action.PayArbitrationFeeBySender) {
            console.log("Rogue: receive() calling payArbitrationFeeBySender pay(%s, %s)", transactionID, amount);
            try caller.payArbitrationFeeBySender{value: amount}(transactionID) {} catch Error(string memory _reason) {
                reason = _reason;
            }
        } else if (action == Action.Revert) {
            console.log("Rogue: reverting");
            revert("Rogue: reverted");
        } else {
            revert("Rogue: invalid action");
        }

        if (bytes(reason).length != 0) {
            console.log("Rogue: call failed with `%s`", reason);
            if (failOnError) {
                revert(reason);
            } else {
                emit ErrorNotHandled(reason);
            }
        }
    }

    function setFailOnError(bool _failOnError) external {
        failOnError = _failOnError;
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

    function pay(uint256 _transactionID, uint256 _amount) external {
        escrow.pay(_transactionID, _amount);
    }

    function reimburse(uint256 _transactionID, uint256 _amountReimbursed) external {
        escrow.reimburse(_transactionID, _amountReimbursed);
    }

    function payArbitrationFeeBySender(uint256 _transactionID) external {
        console.log("Rogue: payArbitrationFeeBySender %s", amount);
        escrow.payArbitrationFeeBySender{value: amount}(_transactionID);
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
/* solhint-enable no-console */
