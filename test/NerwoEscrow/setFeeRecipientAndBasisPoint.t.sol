// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";

import {NerwoEscrow} from "../../src/NerwoEscrow.sol";
import {NerwoTest} from "../NerwoTest.sol";

contract NerwoEscrowTest is NerwoTest {
    function test_setFeeRecipientAndBasisPoint() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.FeeRecipientChanged(feeRecipient, 2000);
        escrow.setFeeRecipientAndBasisPoint(feeRecipient, 2000);
        vm.stopPrank();
    }

    function test_setFeeRecipientAndBasisPoint_Unauth() public {
        vm.startPrank(client);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(client)));
        escrow.setFeeRecipientAndBasisPoint(feeRecipient, 2000);
        vm.stopPrank();
    }

    function test_setFeeRecipientAndBasisPoint_Max() public {
        vm.startPrank(owner);
        vm.expectRevert(NerwoEscrow.InvalidFeeBasisPoint.selector);
        escrow.setFeeRecipientAndBasisPoint(feeRecipient, 2001); // > MAX
        vm.stopPrank();
    }
}
