// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {NerwoCentralizedArbitrator} from "@nerwo/contracts/NerwoCentralizedArbitrator.sol";
import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {NerwoTest} from "@nerwo/test/NerwoTest.sol";

/**
 * @notice PoC for finding C2: arbitration cost must be frozen at the first
 *         payArbitrationFee. After the fix:
 *         - paying the inflated current price reverts (cost is frozen);
 *         - if the arbitrator rejects the frozen value, the second payment reverts
 *           cleanly so no funds are lost and the first party can still timeout.
 *
 *         Without the fix the freelancer could pay the new price, the dispute
 *         was created with the new price, and the contract was left short of
 *         ETH to refund the winner.
 */
contract ArbitrationPriceMidDisputeTest is NerwoTest {
    function _stuckTransaction(uint256 newPrice) internal returns (uint256 transactionID) {
        uint256 amount = 1e18;
        transactionID = createTransaction(client, freelancer, nerwoTestToken, amount);

        // Client pays at the original price; this freezes the cost in the transaction.
        vm.deal(client, ARBITRATION_PRICE);
        vm.prank(client);
        escrow.payArbitrationFee{value: ARBITRATION_PRICE}(transactionID);

        vm.prank(court);
        arbitrator.setArbitrationPrice(newPrice);
    }

    function test_C2_freelancerCannotPayInflatedCost() public {
        uint256 newPrice = ARBITRATION_PRICE * 5;
        uint256 transactionID = _stuckTransaction(newPrice);

        // Post-fix: paying the new (inflated) price must revert because the cost
        // is locked to the value paid by the first party.
        vm.deal(freelancer, newPrice);
        vm.prank(freelancer);
        vm.expectRevert(NerwoEscrow.InvalidAmount.selector);
        escrow.payArbitrationFee{value: newPrice}(transactionID);
    }

    function test_C2_disputeCreationFailsCleanlyOnPriceChange() public {
        uint256 newPrice = ARBITRATION_PRICE * 5;
        uint256 transactionID = _stuckTransaction(newPrice);

        // Freelancer pays the FROZEN cost. The escrow accepts it, but createDispute
        // bubbles up InsufficientPayment from the arbitrator because it still
        // checks the current (now higher) price. The whole call reverts and the
        // freelancer's ETH is fully refunded by the EVM.
        uint256 freelancerEthBefore = ARBITRATION_PRICE;
        vm.deal(freelancer, freelancerEthBefore);

        vm.prank(freelancer);
        vm.expectRevert(NerwoCentralizedArbitrator.InsufficientPayment.selector);
        escrow.payArbitrationFee{value: ARBITRATION_PRICE}(transactionID);

        assertEq(freelancer.balance, freelancerEthBefore, "freelancer ETH preserved");

        // The first party can still recover via timeout — system is not stuck.
        vm.warp(block.timestamp + FEE_TIMEOUT);

        uint256 clientEthBefore = client.balance;
        uint256 escrowEthBefore = address(escrow).balance;

        vm.prank(client);
        escrow.timeOut(transactionID);

        // Client gets the original arbitration deposit back.
        assertEthBalanceIncrease(client, ARBITRATION_PRICE, clientEthBefore);
        assertEthBalanceDecrease(address(escrow), ARBITRATION_PRICE, escrowEthBefore);
    }

    function test_C2_happyPath_bothFeesEqualWhenPriceIsStable() public {
        // Sanity check: when the arbitrator price does not change, both stored
        // fees must be equal to the frozen cost and the dispute resolves cleanly.
        uint256 amount = 1e18;
        uint256 transactionID = createTransaction(client, freelancer, nerwoTestToken, amount);

        uint256 disputeID = payArbitrationFees(transactionID, client, freelancer);
        NerwoEscrow.Transaction memory tx_ = escrow.getTransaction(transactionID);
        assertEq(tx_.clientFee, ARBITRATION_PRICE, "clientFee equals frozen");
        assertEq(tx_.freelancerFee, ARBITRATION_PRICE, "freelancerFee equals frozen");
        assertEq(tx_.arbitrationCost, ARBITRATION_PRICE, "frozen cost stored");

        uint256 freelancerEthBefore = freelancer.balance;

        giveRuling(disputeID, RULING_FREELANCER_WINS);

        assertEthBalanceIncrease(freelancer, ARBITRATION_PRICE, freelancerEthBefore);
    }
}
