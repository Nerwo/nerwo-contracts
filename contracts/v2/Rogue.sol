// SPDX-License-Identifier: MIT
/**
 *  @authors: [@sherpya]
 */
pragma solidity ^0.8;

import "hardhat/console.sol";

interface Escrow {
    function pay(uint _transactionID, uint _amount) external;
}

contract Rogue {
    uint constant ACTION_NONE = 0;
    uint constant ACTION_PAY = 1;
    uint constant ACTION_MAX = 2;

    uint action = ACTION_NONE;
    uint transactionID = 0;
    uint amount = 0;

    fallback() external payable {
        // The fallback function can have the "payable" modifier
        // which means it can accept ether.
        revert();
    }

    receive() external payable {
        Escrow escrow = Escrow(msg.sender);
        if (action == ACTION_NONE) {
            //
        } else if (action == ACTION_PAY) {
            //console.log("Calling pay(%s, %s)", transactionID, amount);
            escrow.pay(transactionID, amount);
            //console.log("Called pay()");
        }
    }

    function setAction(uint _action) public {
        require(_action < ACTION_MAX, "Invalid action");
        action = _action;
    }

    function setTransaction(uint _transactionID, uint _amount) public {
        transactionID = _transactionID;
        amount = _amount;
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
