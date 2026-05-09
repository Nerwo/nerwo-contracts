// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {NerwoTest} from "@nerwo/test/NerwoTest.sol";

/**
 * @notice PoC for finding C2: arbitration cost must be frozen at the first
 *         payArbitrationFee so the second payer cannot be misled by a
 *         mid-dispute price change, and the contract always retains enough
 *         ETH to refund whichever party wins.
 */
contract ArbitrationPriceMidDisputeTest is NerwoTest {
    function test_C2_freelancerCanPayFrozenCostAfterPriceIncrease() public {
        uint256 amount = 1e18;
        uint256 transactionID = createTransaction(client, freelancer, nerwoTestToken, amount);

        // Client pays at the original price.
        vm.deal(client, ARBITRATION_PRICE);
        vm.prank(client);
        escrow.payArbitrationFee{value: ARBITRATION_PRICE}(transactionID);

        // Arbitrator owner doubles the price mid-dispute.
        uint256 newPrice = ARBITRATION_PRICE * 5;
        vm.prank(court);
        arbitrator.setArbitrationPrice(newPrice);

        // Post-fix: the freelancer must pay the FROZEN price (the one client paid).
        vm.deal(freelancer, ARBITRATION_PRICE);
        vm.prank(freelancer);
        escrow.payArbitrationFee{value: ARBITRATION_PRICE}(transactionID);

        // Dispute is created. The contract retained the client's deposit and forwarded
        // an equal amount to the proxy. So contract still has exactly ARBITRATION_PRICE
        // earmarked to refund the winner of arbitration.
        uint256 disputeID = arbitrator.lastDispute();
        giveRuling(disputeID, RULING_FREELANCER_WINS);

        uint256 freelancerEthBefore = freelancer.balance;
        uint256 escrowEthBefore = address(escrow).balance;

        vm.prank(freelancer);
        escrow.acceptRuling(transactionID);

        // Freelancer's arbitration fee is fully refunded (no starvation).
        assertEthBalanceDelta(freelancer, int256(ARBITRATION_PRICE), freelancerEthBefore);
        assertEthBalanceDelta(address(escrow), -int256(ARBITRATION_PRICE), escrowEthBefore);
        assertEq(escrow.pendingWithdrawals(NATIVE_TOKEN, freelancer), 0, "no ETH starvation");
    }

    function test_C2_freelancerCannotPayInflatedCost() public {
        uint256 amount = 1e18;
        uint256 transactionID = createTransaction(client, freelancer, nerwoTestToken, amount);

        vm.deal(client, ARBITRATION_PRICE);
        vm.prank(client);
        escrow.payArbitrationFee{value: ARBITRATION_PRICE}(transactionID);

        uint256 newPrice = ARBITRATION_PRICE * 5;
        vm.prank(court);
        arbitrator.setArbitrationPrice(newPrice);

        // Post-fix: paying the new (inflated) price must revert because the cost
        // is locked to the value paid by the first party.
        vm.deal(freelancer, newPrice);
        vm.prank(freelancer);
        vm.expectRevert(NerwoEscrow.InvalidAmount.selector);
        escrow.payArbitrationFee{value: newPrice}(transactionID);
    }
}
