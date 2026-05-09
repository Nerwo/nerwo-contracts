// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {NerwoCentralizedArbitrator} from "@nerwo/contracts/NerwoCentralizedArbitrator.sol";
import {NerwoTest} from "@nerwo/test/NerwoTest.sol";

contract NerwoEscrowRuleTest is NerwoTest {
    function test_ruleErrors() public {
        (uint256 transactionID, uint256 disputeID, ) = createDispute(nerwoTestToken);

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

    function test_acceptRulingClientWinsErc20() public {
        (uint256 transactionID, uint256 disputeID, uint256 amount) = createDispute(nerwoTestToken);

        (bool isRuled, ) = escrow.fetchRuling(transactionID);
        assertFalse(isRuled);

        giveRuling(disputeID, RULING_CLIENT_WINS);
        uint256 ruling;
        (isRuled, ruling) = escrow.fetchRuling(transactionID);
        assertTrue(isRuled);
        assertEq(ruling, RULING_CLIENT_WINS);

        uint256 clientEthBefore = client.balance;
        uint256 clientTokenBefore = nerwoTestToken.balanceOf(client);
        uint256 escrowTokenBefore = nerwoTestToken.balanceOf(address(escrow));

        vm.prank(client);
        escrow.acceptRuling(transactionID);

        assertEthBalanceDelta(client, int256(ARBITRATION_PRICE), clientEthBefore);
        assertTokenBalanceDelta(nerwoTestToken, client, int256(amount), clientTokenBefore);
        assertTokenBalanceDelta(nerwoTestToken, address(escrow), -int256(amount), escrowTokenBefore);
    }

    function test_acceptRulingFreelancerWinsErc20() public {
        (uint256 transactionID, uint256 disputeID, uint256 amount) = createDispute(nerwoTestToken);
        uint256 feeAmount = escrow.calculateFeeRecipientAmount(amount);

        giveRuling(disputeID, RULING_FREELANCER_WINS);

        uint256 escrowEthBefore = address(escrow).balance;
        uint256 freelancerEthBefore = freelancer.balance;
        uint256 escrowTokenBefore = nerwoTestToken.balanceOf(address(escrow));
        uint256 feeRecipientBefore = nerwoTestToken.balanceOf(feeRecipient);
        uint256 freelancerBefore = nerwoTestToken.balanceOf(freelancer);

        vm.prank(freelancer);
        escrow.acceptRuling(transactionID);

        assertEthBalanceDelta(address(escrow), -int256(ARBITRATION_PRICE), escrowEthBefore);
        assertEthBalanceDelta(freelancer, int256(ARBITRATION_PRICE), freelancerEthBefore);
        assertTokenBalanceDelta(nerwoTestToken, address(escrow), -int256(amount), escrowTokenBefore);
        assertTokenBalanceDelta(nerwoTestToken, feeRecipient, int256(feeAmount), feeRecipientBefore);
        assertTokenBalanceDelta(nerwoTestToken, freelancer, int256(amount - feeAmount), freelancerBefore);
    }

    function test_acceptRulingSplitErc20() public {
        (uint256 transactionID, uint256 disputeID, uint256 amount) = createDispute(nerwoTestToken);
        uint256 splitAmount = amount / 2;
        uint256 splitArbitration = ARBITRATION_PRICE / 2;
        uint256 splitFeeAmount = escrow.calculateFeeRecipientAmount(splitAmount);

        giveRuling(disputeID, RULING_SPLIT);

        uint256 escrowEthBefore = address(escrow).balance;
        uint256 clientEthBefore = client.balance;
        uint256 freelancerEthBefore = freelancer.balance;
        uint256 escrowTokenBefore = nerwoTestToken.balanceOf(address(escrow));
        uint256 feeRecipientBefore = nerwoTestToken.balanceOf(feeRecipient);
        uint256 clientTokenBefore = nerwoTestToken.balanceOf(client);
        uint256 freelancerTokenBefore = nerwoTestToken.balanceOf(freelancer);

        vm.prank(client);
        escrow.acceptRuling(transactionID);

        assertEthBalanceDelta(address(escrow), -int256(ARBITRATION_PRICE), escrowEthBefore);
        assertEthBalanceDelta(client, int256(splitArbitration), clientEthBefore);
        assertEthBalanceDelta(freelancer, int256(splitArbitration), freelancerEthBefore);
        assertTokenBalanceDelta(nerwoTestToken, address(escrow), -int256(splitAmount * 2), escrowTokenBefore);
        assertTokenBalanceDelta(nerwoTestToken, feeRecipient, int256(splitFeeAmount), feeRecipientBefore);
        assertTokenBalanceDelta(nerwoTestToken, client, int256(splitAmount), clientTokenBefore);
        assertTokenBalanceDelta(nerwoTestToken, freelancer, int256(splitAmount - splitFeeAmount), freelancerTokenBefore);
    }

    function test_acceptRulingClientWinsNative() public {
        (uint256 transactionID, uint256 disputeID, uint256 amount) = createDispute(NATIVE_TOKEN);

        giveRuling(disputeID, RULING_CLIENT_WINS);

        uint256 escrowBefore = address(escrow).balance;
        uint256 clientBefore = client.balance;

        vm.prank(client);
        escrow.acceptRuling(transactionID);

        assertEthBalanceDelta(address(escrow), -int256(ARBITRATION_PRICE + amount), escrowBefore);
        assertEthBalanceDelta(client, int256(ARBITRATION_PRICE + amount), clientBefore);
    }

    function test_acceptRulingFreelancerWinsNative() public {
        (uint256 transactionID, uint256 disputeID, uint256 amount) = createDispute(NATIVE_TOKEN);
        uint256 feeAmount = escrow.calculateFeeRecipientAmount(amount);

        giveRuling(disputeID, RULING_FREELANCER_WINS);

        uint256 escrowBefore = address(escrow).balance;
        uint256 feeRecipientBefore = feeRecipient.balance;
        uint256 freelancerBefore = freelancer.balance;

        vm.prank(freelancer);
        escrow.acceptRuling(transactionID);

        assertEthBalanceDelta(address(escrow), -int256(ARBITRATION_PRICE + amount), escrowBefore);
        assertEthBalanceDelta(feeRecipient, int256(feeAmount), feeRecipientBefore);
        assertEthBalanceDelta(freelancer, int256(ARBITRATION_PRICE + amount - feeAmount), freelancerBefore);
    }

    function test_acceptRulingSplitNative() public {
        (uint256 transactionID, uint256 disputeID, uint256 amount) = createDispute(NATIVE_TOKEN);
        uint256 splitAmount = amount / 2;
        uint256 splitArbitration = ARBITRATION_PRICE / 2;
        uint256 splitFeeAmount = escrow.calculateFeeRecipientAmount(splitAmount);

        giveRuling(disputeID, RULING_SPLIT);

        uint256 escrowBefore = address(escrow).balance;
        uint256 feeRecipientBefore = feeRecipient.balance;
        uint256 clientBefore = client.balance;
        uint256 freelancerBefore = freelancer.balance;

        vm.prank(client);
        escrow.acceptRuling(transactionID);

        assertEthBalanceDelta(address(escrow), -int256(ARBITRATION_PRICE + (splitAmount * 2)), escrowBefore);
        assertEthBalanceDelta(feeRecipient, int256(splitFeeAmount), feeRecipientBefore);
        assertEthBalanceDelta(client, int256(splitAmount + splitArbitration), clientBefore);
        assertEthBalanceDelta(freelancer, int256(splitAmount + splitArbitration - splitFeeAmount), freelancerBefore);
    }
}
