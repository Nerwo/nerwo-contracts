// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {SafeTransfer} from "@nerwo/contracts/SafeTransfer.sol";
import {NerwoTest} from "@nerwo/test/NerwoTest.sol";

import {RejectingFeeRecipient} from "@nerwo/test/security/helpers/RejectingFeeRecipient.sol";
import {BlacklistToken} from "@nerwo/test/security/helpers/BlacklistToken.sol";

/**
 * @notice PoC for finding C1: a feeRecipient that cannot receive funds bricks pay()
 *         and ruling execution. Tests assert the post-fix behavior (credit to
 *         pendingWithdrawals instead of revert).
 */
contract FeeRecipientDoSTest is NerwoTest {
    RejectingFeeRecipient internal rejectingFeeRecipient;
    BlacklistToken internal blacklistToken;

    function _useRejectingFeeRecipient() internal returns (address) {
        rejectingFeeRecipient = new RejectingFeeRecipient();
        vm.prank(owner);
        escrow.setFeeRecipientAndBasisPoint(address(rejectingFeeRecipient), FEE_RECIPIENT_BASIS_POINT);
        return address(rejectingFeeRecipient);
    }

    function _useBlacklistToken() internal returns (BlacklistToken) {
        blacklistToken = new BlacklistToken();
        blacklistToken.setBlacklisted(feeRecipient, true);

        NerwoEscrow.TokenAllow[] memory list = new NerwoEscrow.TokenAllow[](1);
        list[0] = NerwoEscrow.TokenAllow(blacklistToken, true);
        vm.prank(owner);
        escrow.changeWhitelist(list);
        return blacklistToken;
    }

    /* ------------------------------------------------------------ T-C1a */
    function test_C1a_payNative_creditsFeeRecipientWhenRejecting() public {
        address rejecting = _useRejectingFeeRecipient();
        uint256 amount = 1 ether;
        uint256 feeAmount = escrow.calculateFeeRecipientAmount(amount);
        uint256 freelancerBefore = freelancer.balance;

        uint256 transactionID = createTransaction(client, freelancer, NATIVE_TOKEN, amount);

        vm.prank(client);
        escrow.pay(transactionID);

        assertEq(escrow.pendingWithdrawals(NATIVE_TOKEN, rejecting), feeAmount, "fee should be credited");
        assertEthBalanceIncrease(freelancer, amount - feeAmount, freelancerBefore);
    }

    /* ------------------------------------------------------------ T-C1b */
    function test_C1b_acceptRulingFreelancerWins_creditsFeeRecipientWhenBlacklisted() public {
        BlacklistToken token = _useBlacklistToken();

        uint256 amount = 1e18;
        token.mint(client, amount);
        vm.prank(client);
        token.approve(address(escrow), amount);

        vm.prank(client);
        uint256 transactionID = escrow.createTransaction(nextOfferID(), token, amount, freelancer);

        vm.deal(client, ARBITRATION_PRICE);
        vm.prank(client);
        escrow.payArbitrationFee{value: ARBITRATION_PRICE}(transactionID);

        vm.deal(freelancer, ARBITRATION_PRICE);
        vm.prank(freelancer);
        escrow.payArbitrationFee{value: ARBITRATION_PRICE}(transactionID);

        uint256 disputeID = arbitrator.lastDispute();
        giveRuling(disputeID, RULING_FREELANCER_WINS);

        uint256 feeAmount = escrow.calculateFeeRecipientAmount(amount);
        uint256 freelancerBefore = token.balanceOf(freelancer);

        vm.prank(freelancer);
        escrow.acceptRuling(transactionID);

        assertEq(escrow.pendingWithdrawals(token, feeRecipient), feeAmount, "fee should be credited");
        assertEq(token.balanceOf(freelancer) - freelancerBefore, amount - feeAmount, "freelancer paid net");
    }

    /* ------------------------------------------------------------ T-C1c */
    function test_C1c_acceptRulingSplit_creditsFeeRecipientWhenBlacklisted() public {
        BlacklistToken token = _useBlacklistToken();

        uint256 amount = 1e18;
        token.mint(client, amount);
        vm.prank(client);
        token.approve(address(escrow), amount);

        vm.prank(client);
        uint256 transactionID = escrow.createTransaction(nextOfferID(), token, amount, freelancer);

        vm.deal(client, ARBITRATION_PRICE);
        vm.prank(client);
        escrow.payArbitrationFee{value: ARBITRATION_PRICE}(transactionID);

        vm.deal(freelancer, ARBITRATION_PRICE);
        vm.prank(freelancer);
        escrow.payArbitrationFee{value: ARBITRATION_PRICE}(transactionID);

        uint256 disputeID = arbitrator.lastDispute();
        giveRuling(disputeID, RULING_SPLIT);

        uint256 splitAmount = amount / 2;
        uint256 splitFee = escrow.calculateFeeRecipientAmount(splitAmount);
        uint256 freelancerBefore = token.balanceOf(freelancer);
        uint256 clientBefore = token.balanceOf(client);

        vm.prank(client);
        escrow.acceptRuling(transactionID);

        assertEq(escrow.pendingWithdrawals(token, feeRecipient), splitFee, "fee should be credited");
        assertEq(token.balanceOf(client) - clientBefore, splitAmount, "client gets half");
        assertEq(token.balanceOf(freelancer) - freelancerBefore, splitAmount - splitFee, "freelancer gets half net");
    }
}
