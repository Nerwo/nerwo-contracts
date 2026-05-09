// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {NerwoTest} from "@nerwo/test/NerwoTest.sol";

contract NerwoEscrowFlowsTest is NerwoTest {
    function test_changeWhitelist() public {
        NerwoEscrow.TokenAllow[] memory supportedTokens = new NerwoEscrow.TokenAllow[](1);
        supportedTokens[0] = NerwoEscrow.TokenAllow(nerwoTestToken, true);

        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.WhitelistChanged(nerwoTestToken, true);

        vm.prank(owner);
        escrow.changeWhitelist(supportedTokens);
    }

    function test_changeWhitelistOnlyOwner() public {
        NerwoEscrow.TokenAllow[] memory supportedTokens = new NerwoEscrow.TokenAllow[](0);

        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, client));
        escrow.changeWhitelist(supportedTokens);
    }

    function test_setFeeRecipientAndBasisPoint() public {
        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.FeeRecipientChanged(client, 2000);

        vm.prank(owner);
        escrow.setFeeRecipientAndBasisPoint(client, 2000);
    }

    function test_setFeeRecipientAndBasisPointInvalidFee() public {
        vm.prank(owner);
        vm.expectRevert(NerwoEscrow.InvalidFeeBasisPoint.selector);
        escrow.setFeeRecipientAndBasisPoint(client, 2001);
    }

    function test_receiveAcceptsEthOnlyFromOwner() public {
        uint256 amount = randomAmount();
        vm.deal(owner, amount);

        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.ContractFunded(owner, amount);

        vm.prank(owner);
        (bool success, ) = address(escrow).call{value: amount}("");
        assertTrue(success);
        assertEq(address(escrow).balance, amount);

        vm.deal(client, amount);
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, client));
        (success, ) = address(escrow).call{value: amount}("");
        success;
    }

    function test_payErc20() public {
        uint256 amount = randomAmount();
        uint256 transactionID = createTransaction(client, freelancer, nerwoTestToken, amount);
        uint256 feeAmount = escrow.calculateFeeRecipientAmount(amount);

        uint256 escrowBefore = nerwoTestToken.balanceOf(address(escrow));
        uint256 feeRecipientBefore = nerwoTestToken.balanceOf(feeRecipient);
        uint256 freelancerBefore = nerwoTestToken.balanceOf(freelancer);

        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.FeeRecipientPayment(transactionID, feeRecipient, nerwoTestToken, feeAmount);
        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.Payment(transactionID, client, freelancer, nerwoTestToken, amount - feeAmount);

        vm.prank(client);
        escrow.pay(transactionID);

        assertTokenBalanceDelta(nerwoTestToken, address(escrow), -int256(amount), escrowBefore);
        assertTokenBalanceDelta(nerwoTestToken, feeRecipient, int256(feeAmount), feeRecipientBefore);
        assertTokenBalanceDelta(nerwoTestToken, freelancer, int256(amount - feeAmount), freelancerBefore);

        vm.prank(client);
        vm.expectRevert(NerwoEscrow.InvalidAmount.selector);
        escrow.pay(transactionID);
    }

    function test_payNative() public {
        uint256 amount = randomAmount();
        uint256 transactionID = createTransaction(client, freelancer, NATIVE_TOKEN, amount);
        uint256 feeAmount = escrow.calculateFeeRecipientAmount(amount);

        uint256 escrowBefore = address(escrow).balance;
        uint256 feeRecipientBefore = feeRecipient.balance;
        uint256 freelancerBefore = freelancer.balance;

        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.FeeRecipientPayment(transactionID, feeRecipient, NATIVE_TOKEN, feeAmount);
        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.Payment(transactionID, client, freelancer, NATIVE_TOKEN, amount - feeAmount);

        vm.prank(client);
        escrow.pay(transactionID);

        assertEthBalanceDelta(address(escrow), -int256(amount), escrowBefore);
        assertEthBalanceDelta(feeRecipient, int256(feeAmount), feeRecipientBefore);
        assertEthBalanceDelta(freelancer, int256(amount - feeAmount), freelancerBefore);

        vm.prank(client);
        vm.expectRevert(NerwoEscrow.InvalidAmount.selector);
        escrow.pay(transactionID);
    }

    function test_reimburseErc20() public {
        uint256 amount = randomAmount();
        uint256 transactionID = createTransaction(client, freelancer, nerwoTestToken, amount);

        uint256 escrowBefore = nerwoTestToken.balanceOf(address(escrow));
        uint256 clientBefore = nerwoTestToken.balanceOf(client);

        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.Reimburse(transactionID, freelancer, client, nerwoTestToken, amount);

        vm.prank(freelancer);
        escrow.reimburse(transactionID);

        assertTokenBalanceDelta(nerwoTestToken, address(escrow), -int256(amount), escrowBefore);
        assertTokenBalanceDelta(nerwoTestToken, client, int256(amount), clientBefore);

        vm.prank(freelancer);
        vm.expectRevert(NerwoEscrow.InvalidAmount.selector);
        escrow.reimburse(transactionID);
    }

    function test_reimburseNative() public {
        uint256 amount = randomAmount();
        uint256 transactionID = createTransaction(client, freelancer, NATIVE_TOKEN, amount);

        uint256 escrowBefore = address(escrow).balance;
        uint256 clientBefore = client.balance;

        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.Reimburse(transactionID, freelancer, client, NATIVE_TOKEN, amount);

        vm.prank(freelancer);
        escrow.reimburse(transactionID);

        assertEthBalanceDelta(address(escrow), -int256(amount), escrowBefore);
        assertEthBalanceDelta(client, int256(amount), clientBefore);

        vm.prank(freelancer);
        vm.expectRevert(NerwoEscrow.InvalidAmount.selector);
        escrow.reimburse(transactionID);
    }

    function test_timeoutByClient() public {
        uint256 amount = randomAmount();
        uint256 transactionID = createTransaction(client, freelancer, nerwoTestToken, amount);

        vm.deal(client, ARBITRATION_PRICE);
        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.HasToPayFee(transactionID, freelancer);
        vm.prank(client);
        escrow.payArbitrationFee{value: ARBITRATION_PRICE}(transactionID);

        vm.prank(client);
        vm.expectRevert(NerwoEscrow.NoTimeout.selector);
        escrow.timeOut(transactionID);

        vm.warp(block.timestamp + FEE_TIMEOUT);

        uint256 escrowEthBefore = address(escrow).balance;
        uint256 clientEthBefore = client.balance;
        uint256 escrowTokenBefore = nerwoTestToken.balanceOf(address(escrow));
        uint256 clientTokenBefore = nerwoTestToken.balanceOf(client);

        vm.prank(client);
        escrow.timeOut(transactionID);

        assertEthBalanceDelta(address(escrow), -int256(ARBITRATION_PRICE), escrowEthBefore);
        assertEthBalanceDelta(client, int256(ARBITRATION_PRICE), clientEthBefore);
        assertTokenBalanceDelta(nerwoTestToken, address(escrow), -int256(amount), escrowTokenBefore);
        assertTokenBalanceDelta(nerwoTestToken, client, int256(amount), clientTokenBefore);
    }

    function test_timeoutByFreelancer() public {
        uint256 amount = randomAmount();
        uint256 feeAmount = escrow.calculateFeeRecipientAmount(amount);
        uint256 transactionID = createTransaction(client, freelancer, nerwoTestToken, amount);

        vm.deal(freelancer, ARBITRATION_PRICE);
        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.HasToPayFee(transactionID, client);
        vm.prank(freelancer);
        escrow.payArbitrationFee{value: ARBITRATION_PRICE}(transactionID);

        vm.prank(freelancer);
        vm.expectRevert(NerwoEscrow.NoTimeout.selector);
        escrow.timeOut(transactionID);

        vm.warp(block.timestamp + FEE_TIMEOUT);

        uint256 escrowEthBefore = address(escrow).balance;
        uint256 freelancerEthBefore = freelancer.balance;
        uint256 escrowTokenBefore = nerwoTestToken.balanceOf(address(escrow));
        uint256 feeRecipientBefore = nerwoTestToken.balanceOf(feeRecipient);
        uint256 freelancerTokenBefore = nerwoTestToken.balanceOf(freelancer);

        vm.prank(freelancer);
        escrow.timeOut(transactionID);

        assertEthBalanceDelta(address(escrow), -int256(ARBITRATION_PRICE), escrowEthBefore);
        assertEthBalanceDelta(freelancer, int256(ARBITRATION_PRICE), freelancerEthBefore);
        assertTokenBalanceDelta(nerwoTestToken, address(escrow), -int256(amount), escrowTokenBefore);
        assertTokenBalanceDelta(nerwoTestToken, feeRecipient, int256(feeAmount), feeRecipientBefore);
        assertTokenBalanceDelta(nerwoTestToken, freelancer, int256(amount - feeAmount), freelancerTokenBefore);
    }

    function test_timeoutInvalidStatus() public {
        uint256 transactionID = createTransaction(client, freelancer, nerwoTestToken, randomAmount());

        vm.warp(block.timestamp + FEE_TIMEOUT);
        vm.prank(client);
        vm.expectRevert(NerwoEscrow.InvalidStatus.selector);
        escrow.timeOut(transactionID);
    }
}
