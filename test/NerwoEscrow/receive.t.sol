// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";

import {NerwoTest} from "../NerwoTest.sol";

contract NerwoEscrowTest is NerwoTest {
    function test_sendNativeFromOwner() public {
        uint256 escrowBalance = address(escrow).balance;
        startHoax(owner, 2 ether);
        payable(escrow).transfer(1 ether);
        vm.stopPrank();
        assertEq(address(escrow).balance, escrowBalance + 1 ether);
    }

    function test_sendNative() public {
        uint256 escrowBalance = address(escrow).balance;
        startHoax(feeRecipient, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(feeRecipient)));
        payable(escrow).transfer(1 ether);
        vm.stopPrank();
        assertEq(address(escrow).balance, escrowBalance);
    }
}
