// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {NerwoTest} from "../NerwoTest.sol";

contract NerwoEscrowTest is NerwoTest {
    function test_pay_erc20() public {
        uint256 amount = randomAmount();
        uint256 transactionId = createTransaction(client, freelancer, nerwoTestToken, amount);
        uint256 feeAmount = escrow.calculateFeeRecipientAmount(amount);

        vm.startPrank(client);
        uint256 escrowBalance = nerwoTestToken.balanceOf(address(escrow));
        uint256 feeRecipientBalance = nerwoTestToken.balanceOf(feeRecipient);
        uint256 freelancerBalance = nerwoTestToken.balanceOf(freelancer);
        escrow.pay(transactionId);
        assertEq(nerwoTestToken.balanceOf(address(escrow)), escrowBalance - amount);
        assertEq(nerwoTestToken.balanceOf(feeRecipient), feeRecipientBalance + feeAmount);
        assertEq(nerwoTestToken.balanceOf(freelancer), freelancerBalance + amount - feeAmount);
        vm.stopPrank();
    }

    function test_pay_native() public {
        uint256 amount = randomAmount();
        uint256 transactionId = createTransaction(client, freelancer, NATIVE_TOKEN, amount);
        uint256 feeAmount = escrow.calculateFeeRecipientAmount(amount);

        vm.startPrank(client);
        uint256 escrowBalance = address(escrow).balance;
        uint256 feeRecipientBalance = feeRecipient.balance;
        uint256 freelancerBalance = freelancer.balance;
        escrow.pay(transactionId);
        assertEq(address(escrow).balance, escrowBalance - amount);
        assertEq(feeRecipient.balance, feeRecipientBalance + feeAmount);
        assertEq(freelancer.balance, freelancerBalance + amount - feeAmount);
        vm.stopPrank();
    }
}
