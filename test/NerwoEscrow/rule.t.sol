// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {NerwoCentralizedArbitrator} from "@nerwo/contracts/NerwoCentralizedArbitrator.sol";
import {NerwoTest} from "@nerwo/test/NerwoTest.sol";

contract NerwoEscrowRuleTest is NerwoTest {
    function test_ruleErrors() public {
        (uint256 transactionID, uint256 disputeID,) = createDispute(nerwoTestToken);

        vm.prank(feeRecipient);
        vm.expectRevert();
        arbitrator.giveRuling(disputeID, RULING_SPLIT);

        vm.prank(court);
        vm.expectRevert(NerwoCentralizedArbitrator.InvalidDispute.selector);
        arbitrator.giveRuling(0, RULING_SPLIT);

        vm.prank(client);
        vm.expectRevert(NerwoEscrow.InvalidStatus.selector);
        escrow.pay(transactionID);
    }

    function test_ruleClientWinsErc20() public {
        (uint256 transactionID, uint256 disputeID, uint256 amount) = createDispute(nerwoTestToken);

        uint256 clientEthBefore = client.balance;
        uint256 clientTokenBefore = nerwoTestToken.balanceOf(client);
        uint256 escrowTokenBefore = nerwoTestToken.balanceOf(address(escrow));

        giveRuling(disputeID, RULING_CLIENT_WINS);

        assertEthBalanceIncrease(client, ARBITRATION_PRICE, clientEthBefore);
        assertTokenBalanceIncrease(nerwoTestToken, client, amount, clientTokenBefore);
        assertTokenBalanceDecrease(nerwoTestToken, address(escrow), amount, escrowTokenBefore);

        NerwoEscrow.Transaction memory transaction = escrow.getTransaction(transactionID);
        assertEq(uint256(transaction.status), uint256(NerwoEscrow.Status.Resolved));
        assertEq(transaction.ruling, RULING_CLIENT_WINS);
    }

    function test_ruleFreelancerWinsErc20() public {
        (, uint256 disputeID, uint256 amount) = createDispute(nerwoTestToken);
        uint256 feeAmount = escrow.calculateFeeRecipientAmount(amount);

        uint256 escrowEthBefore = address(escrow).balance;
        uint256 freelancerEthBefore = freelancer.balance;
        uint256 escrowTokenBefore = nerwoTestToken.balanceOf(address(escrow));
        uint256 feeRecipientBefore = nerwoTestToken.balanceOf(feeRecipient);
        uint256 freelancerBefore = nerwoTestToken.balanceOf(freelancer);

        giveRuling(disputeID, RULING_FREELANCER_WINS);

        assertEthBalanceDecrease(address(escrow), ARBITRATION_PRICE, escrowEthBefore);
        assertEthBalanceIncrease(freelancer, ARBITRATION_PRICE, freelancerEthBefore);
        assertTokenBalanceDecrease(nerwoTestToken, address(escrow), amount, escrowTokenBefore);
        assertTokenBalanceIncrease(nerwoTestToken, feeRecipient, feeAmount, feeRecipientBefore);
        assertTokenBalanceIncrease(nerwoTestToken, freelancer, amount - feeAmount, freelancerBefore);
    }

    function test_ruleSplitErc20() public {
        (uint256 transactionID, uint256 disputeID, uint256 amount) = createDispute(nerwoTestToken);
        uint256 splitAmount = amount / 2;
        uint256 splitArbitration = ARBITRATION_PRICE / 2;
        uint256 splitFeeAmount = escrow.calculateFeeRecipientAmount(splitAmount);

        uint256 escrowEthBefore = address(escrow).balance;
        uint256 clientEthBefore = client.balance;
        uint256 freelancerEthBefore = freelancer.balance;
        uint256 escrowTokenBefore = nerwoTestToken.balanceOf(address(escrow));
        uint256 feeRecipientBefore = nerwoTestToken.balanceOf(feeRecipient);
        uint256 clientTokenBefore = nerwoTestToken.balanceOf(client);
        uint256 freelancerTokenBefore = nerwoTestToken.balanceOf(freelancer);

        giveRuling(disputeID, RULING_SPLIT);

        assertEthBalanceDecrease(address(escrow), ARBITRATION_PRICE, escrowEthBefore);
        assertEthBalanceIncrease(client, splitArbitration, clientEthBefore);
        assertEthBalanceIncrease(freelancer, splitArbitration, freelancerEthBefore);
        assertTokenBalanceDecrease(nerwoTestToken, address(escrow), splitAmount * 2, escrowTokenBefore);
        assertTokenBalanceIncrease(nerwoTestToken, feeRecipient, splitFeeAmount, feeRecipientBefore);
        assertTokenBalanceIncrease(nerwoTestToken, client, splitAmount, clientTokenBefore);
        assertTokenBalanceIncrease(nerwoTestToken, freelancer, splitAmount - splitFeeAmount, freelancerTokenBefore);
    }

    function test_ruleClientWinsNative() public {
        (, uint256 disputeID, uint256 amount) = createDispute(NATIVE_TOKEN);

        uint256 escrowBefore = address(escrow).balance;
        uint256 clientBefore = client.balance;

        giveRuling(disputeID, RULING_CLIENT_WINS);

        assertEthBalanceDecrease(address(escrow), ARBITRATION_PRICE + amount, escrowBefore);
        assertEthBalanceIncrease(client, ARBITRATION_PRICE + amount, clientBefore);
    }

    function test_ruleFreelancerWinsNative() public {
        (, uint256 disputeID, uint256 amount) = createDispute(NATIVE_TOKEN);
        uint256 feeAmount = escrow.calculateFeeRecipientAmount(amount);

        uint256 escrowBefore = address(escrow).balance;
        uint256 feeRecipientBefore = feeRecipient.balance;
        uint256 freelancerBefore = freelancer.balance;

        giveRuling(disputeID, RULING_FREELANCER_WINS);

        assertEthBalanceDecrease(address(escrow), ARBITRATION_PRICE + amount, escrowBefore);
        assertEthBalanceIncrease(feeRecipient, feeAmount, feeRecipientBefore);
        assertEthBalanceIncrease(freelancer, ARBITRATION_PRICE + amount - feeAmount, freelancerBefore);
    }

    function test_ruleSplitNative() public {
        (, uint256 disputeID, uint256 amount) = createDispute(NATIVE_TOKEN);
        uint256 splitAmount = amount / 2;
        uint256 splitArbitration = ARBITRATION_PRICE / 2;
        uint256 splitFeeAmount = escrow.calculateFeeRecipientAmount(splitAmount);

        uint256 escrowBefore = address(escrow).balance;
        uint256 feeRecipientBefore = feeRecipient.balance;
        uint256 clientBefore = client.balance;
        uint256 freelancerBefore = freelancer.balance;

        giveRuling(disputeID, RULING_SPLIT);

        assertEthBalanceDecrease(address(escrow), ARBITRATION_PRICE + (splitAmount * 2), escrowBefore);
        assertEthBalanceIncrease(feeRecipient, splitFeeAmount, feeRecipientBefore);
        assertEthBalanceIncrease(client, splitAmount + splitArbitration, clientBefore);
        assertEthBalanceIncrease(freelancer, splitAmount + splitArbitration - splitFeeAmount, freelancerBefore);
    }
}
