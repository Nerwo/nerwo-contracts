// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract RejectingFeeRecipient {
    error ETHRejected();

    receive() external payable {
        revert ETHRejected();
    }
}
