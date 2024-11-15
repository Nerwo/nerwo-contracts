// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {NerwoEscrow} from "../../src/NerwoEscrow.sol";
import {NerwoTest} from "../NerwoTest.sol";

contract NerwoEscrowTest is NerwoTest {
    function test_reimburse_erc20() public {
        uint256 amount = randomAmount();
        uint256 transactionId = createTransaction(client, freelancer, nerwoTestToken, amount);

        vm.startPrank(freelancer);
        uint256 escrowBalance = nerwoTestToken.balanceOf(address(escrow));
        uint256 clientBalance = nerwoTestToken.balanceOf(client);
        uint256 freelancerBalance = nerwoTestToken.balanceOf(freelancer);
        escrow.reimburse(transactionId);
        assertEq(nerwoTestToken.balanceOf(address(escrow)), escrowBalance - amount);
        assertEq(nerwoTestToken.balanceOf(client), clientBalance + amount);
        assertEq(nerwoTestToken.balanceOf(freelancer), freelancerBalance);
        vm.stopPrank();
    }

    function test_reimburse_native() public {
        uint256 amount = randomAmount();
        uint256 transactionId = createTransaction(client, freelancer, NATIVE_TOKEN, amount);

        vm.startPrank(freelancer);
        uint256 escrowBalance = address(escrow).balance;
        uint256 clientBalance = client.balance;
        uint256 freelancerBalance = freelancer.balance;
        escrow.reimburse(transactionId);
        assertEq(address(escrow).balance, escrowBalance - amount);
        assertEq(client.balance, clientBalance + amount);
        assertEq(freelancer.balance, freelancerBalance);
        vm.stopPrank();
    }

    function test_reimburse_invalidCaller() public {
        uint256 amount = randomAmount();
        uint256 transactionId = createTransaction(client, freelancer, NATIVE_TOKEN, amount);

        vm.startPrank(client);
        vm.expectRevert(NerwoEscrow.InvalidCaller.selector);
        escrow.reimburse(transactionId);
        vm.stopPrank();
    }
}
