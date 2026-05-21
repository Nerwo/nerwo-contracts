// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {NerwoTest} from "@nerwo/test/NerwoTest.sol";

contract ToggleETHReceiver {
    bool public acceptETH;

    receive() external payable {
        require(acceptETH, "ETH rejected");
    }

    function setAcceptETH(bool acceptETH_) external {
        acceptETH = acceptETH_;
    }

    function claimWithdrawal(NerwoEscrow escrow, IERC20 token) external {
        escrow.claimWithdrawal(token);
    }
}

contract NerwoEscrowFlowsTest is NerwoTest {
    function test_constructorEnablesNativeTokenUnlimited() public {
        address[] memory arbitrators = new address[](2);
        arbitrators[0] = address(arbitrator);
        arbitrators[1] = address(arbitrator);

        NerwoEscrow freshEscrow =
            new NerwoEscrow(owner, arbitrators, "/ipfs/something", feeRecipient, FEE_RECIPIENT_BASIS_POINT);

        assertEq(freshEscrow.amountCaps(NATIVE_TOKEN), freshEscrow.CAP_UNLIMITED());
    }

    function test_changeTokenCap() public {
        uint256 cap = 5_000 * 10 ** nerwoTestToken.decimals();

        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.TokenCapChanged(nerwoTestToken, cap);

        vm.prank(owner);
        escrow.changeTokenCap(nerwoTestToken, cap);

        assertEq(escrow.amountCaps(nerwoTestToken), cap);
    }

    function test_changeTokenCapOnlyOwner() public {
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, client));
        escrow.changeTokenCap(nerwoTestToken, 0);
    }

    function test_changeTokenCapZeroDisablesToken() public {
        uint256 amount = randomAmount();
        bytes16 offerID = nextOfferID();

        vm.prank(owner);
        escrow.changeTokenCap(nerwoTestToken, 0);

        vm.startPrank(client);
        nerwoTestToken.mint(amount);
        nerwoTestToken.approve(address(escrow), amount);
        vm.expectRevert(NerwoEscrow.InvalidToken.selector);
        escrow.createTransaction(offerID, nerwoTestToken, amount, freelancer);
        vm.stopPrank();
    }

    function test_changeTokenCapZeroDisablesNativeToken() public {
        uint256 amount = randomAmount();
        bytes16 offerID = nextOfferID();

        vm.prank(owner);
        escrow.changeTokenCap(NATIVE_TOKEN, 0);

        startHoax(client, amount);
        vm.expectRevert(NerwoEscrow.InvalidToken.selector);
        escrow.createTransaction{value: amount}(offerID, NATIVE_TOKEN, amount, freelancer);
        vm.stopPrank();
    }

    function test_createTransactionAcceptsAmountAtTokenCap() public {
        uint256 cap = randomAmount();

        vm.prank(owner);
        escrow.changeTokenCap(nerwoTestToken, cap);

        createTransaction(client, freelancer, nerwoTestToken, cap);
    }

    function test_createTransactionRejectsAmountAboveTokenCap() public {
        uint256 cap = randomAmount();
        uint256 amount = cap + 1;
        bytes16 offerID = nextOfferID();

        vm.prank(owner);
        escrow.changeTokenCap(nerwoTestToken, cap);

        vm.startPrank(client);
        nerwoTestToken.mint(amount);
        nerwoTestToken.approve(address(escrow), amount);
        vm.expectRevert(NerwoEscrow.InvalidAmount.selector);
        escrow.createTransaction(offerID, nerwoTestToken, amount, freelancer);
        vm.stopPrank();
    }

    function test_createTransactionAcceptsAmountAtNativeTokenCap() public {
        createTransaction(client, freelancer, NATIVE_TOKEN, NATIVE_TOKEN_CAP);
    }

    function test_createTransactionRejectsAmountAboveNativeTokenCap() public {
        uint256 amount = NATIVE_TOKEN_CAP + 1;
        bytes16 offerID = nextOfferID();

        startHoax(client, amount);
        vm.expectRevert(NerwoEscrow.InvalidAmount.selector);
        escrow.createTransaction{value: amount}(offerID, NATIVE_TOKEN, amount, freelancer);
        vm.stopPrank();
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

    function test_setFeeRecipientAndBasisPointRejectsHugeValue() public {
        vm.prank(owner);
        vm.expectRevert(NerwoEscrow.InvalidFeeBasisPoint.selector);
        escrow.setFeeRecipientAndBasisPoint(client, type(uint256).max);
    }

    function test_payUsesTransactionFeeSnapshot() public {
        uint256 amount = randomAmount();
        uint256 transactionID = createTransaction(client, freelancer, nerwoTestToken, amount);
        uint256 snapshottedFeeAmount = (amount * FEE_RECIPIENT_BASIS_POINT) / 10_000;
        address newFeeRecipient = makeAddr("newFeeRecipient");

        vm.prank(owner);
        escrow.setFeeRecipientAndBasisPoint(newFeeRecipient, 2_000);

        uint256 oldFeeRecipientBefore = nerwoTestToken.balanceOf(feeRecipient);
        uint256 newFeeRecipientBefore = nerwoTestToken.balanceOf(newFeeRecipient);
        uint256 freelancerBefore = nerwoTestToken.balanceOf(freelancer);

        vm.prank(client);
        escrow.pay(transactionID);

        assertTokenBalanceIncrease(nerwoTestToken, feeRecipient, snapshottedFeeAmount, oldFeeRecipientBefore);
        assertEq(nerwoTestToken.balanceOf(newFeeRecipient), newFeeRecipientBefore);
        assertTokenBalanceIncrease(nerwoTestToken, freelancer, amount - snapshottedFeeAmount, freelancerBefore);
    }

    function test_payCreditsPendingWithdrawalWhenNativeTransferFails() public {
        ToggleETHReceiver receiver = new ToggleETHReceiver();
        uint256 amount = randomAmount();
        uint256 feeAmount = escrow.calculateFeeRecipientAmount(amount);
        uint256 expectedPending = amount - feeAmount;
        uint256 transactionID = createTransaction(client, address(receiver), NATIVE_TOKEN, amount);

        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.WithdrawalCredited(address(receiver), NATIVE_TOKEN, expectedPending);

        vm.prank(client);
        escrow.pay(transactionID);

        assertEq(escrow.pendingWithdrawals(NATIVE_TOKEN, address(receiver)), expectedPending);
        assertEq(address(receiver).balance, 0);

        uint256 escrowBefore = address(escrow).balance;
        receiver.setAcceptETH(true);
        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.WithdrawalClaimed(address(receiver), NATIVE_TOKEN, expectedPending);
        receiver.claimWithdrawal(escrow, NATIVE_TOKEN);

        assertEq(escrow.pendingWithdrawals(NATIVE_TOKEN, address(receiver)), 0);
        assertEq(address(receiver).balance, expectedPending);
        assertEthBalanceDecrease(address(escrow), expectedPending, escrowBefore);
    }

    function test_receiveAcceptsEthOnlyFromOwner() public {
        uint256 amount = randomAmount();
        vm.deal(owner, amount);

        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.ContractFunded(owner, amount);

        vm.prank(owner);
        (bool success,) = address(escrow).call{value: amount}("");
        assertTrue(success);
        assertEq(address(escrow).balance, amount);

        vm.deal(client, amount);
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, client));
        (success,) = address(escrow).call{value: amount}("");
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

        assertTokenBalanceDecrease(nerwoTestToken, address(escrow), amount, escrowBefore);
        assertTokenBalanceIncrease(nerwoTestToken, feeRecipient, feeAmount, feeRecipientBefore);
        assertTokenBalanceIncrease(nerwoTestToken, freelancer, amount - feeAmount, freelancerBefore);

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

        assertEthBalanceDecrease(address(escrow), amount, escrowBefore);
        assertEthBalanceIncrease(feeRecipient, feeAmount, feeRecipientBefore);
        assertEthBalanceIncrease(freelancer, amount - feeAmount, freelancerBefore);

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

        assertTokenBalanceDecrease(nerwoTestToken, address(escrow), amount, escrowBefore);
        assertTokenBalanceIncrease(nerwoTestToken, client, amount, clientBefore);

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

        assertEthBalanceDecrease(address(escrow), amount, escrowBefore);
        assertEthBalanceIncrease(client, amount, clientBefore);

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

        assertEthBalanceDecrease(address(escrow), ARBITRATION_PRICE, escrowEthBefore);
        assertEthBalanceIncrease(client, ARBITRATION_PRICE, clientEthBefore);
        assertTokenBalanceDecrease(nerwoTestToken, address(escrow), amount, escrowTokenBefore);
        assertTokenBalanceIncrease(nerwoTestToken, client, amount, clientTokenBefore);
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

        assertEthBalanceDecrease(address(escrow), ARBITRATION_PRICE, escrowEthBefore);
        assertEthBalanceIncrease(freelancer, ARBITRATION_PRICE, freelancerEthBefore);
        assertTokenBalanceDecrease(nerwoTestToken, address(escrow), amount, escrowTokenBefore);
        assertTokenBalanceIncrease(nerwoTestToken, feeRecipient, feeAmount, feeRecipientBefore);
        assertTokenBalanceIncrease(nerwoTestToken, freelancer, amount - feeAmount, freelancerTokenBefore);
    }

    function test_timeoutInvalidStatus() public {
        uint256 transactionID = createTransaction(client, freelancer, nerwoTestToken, randomAmount());

        vm.warp(block.timestamp + FEE_TIMEOUT);
        vm.prank(client);
        vm.expectRevert(NerwoEscrow.InvalidStatus.selector);
        escrow.timeOut(transactionID);
    }
}
