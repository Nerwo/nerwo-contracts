// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";

import {NerwoTest} from "@nerwo/test/NerwoTest.sol";

contract FeeOnTransferToken is ERC20 {
    constructor() ERC20("Fee Token", "FEE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from == address(0) || to == address(0)) {
            super._update(from, to, amount);
            return;
        }

        uint256 fee = amount / 10;
        super._update(from, address(0), fee);
        super._update(from, to, amount - fee);
    }
}

contract NerwoEscrowTest is NerwoTest {
    // Creating a simple transaction
    function test_createSimpleTransaction() public {
        createTransaction(client, freelancer, nerwoTestToken, randomAmount());
    }

    // Creating a transaction with native token
    function test_createSimpleTransactionNativeToken() public {
        createTransaction(client, freelancer, NATIVE_TOKEN, randomAmount());
    }

    // Invalid Token
    function test_createTransactionInvalidToken() public {
        uint256 amount = randomAmount();
        vm.startPrank(client);
        vm.expectRevert(NerwoEscrow.InvalidToken.selector);
        escrow.createTransaction(IERC20(address(escrow)), amount, freelancer);
        vm.stopPrank();
    }

    // Creating a transaction with badly mixed arguments
    function test_createTransactionMixedArguments() public {
        uint256 amount = randomAmount();
        startHoax(client, amount);
        vm.expectRevert(NerwoEscrow.InvalidToken.selector);
        escrow.createTransaction{value: amount}(nerwoTestToken, amount, freelancer);
        vm.stopPrank();
    }

    // Creating a transaction with myself
    function test_createTransactionWithMyself() public {
        uint256 amount = randomAmount();
        startHoax(client, amount);
        vm.expectRevert(NerwoEscrow.InvalidCaller.selector);
        escrow.createTransaction{value: amount}(NATIVE_TOKEN, amount, client);
        vm.stopPrank();
    }

    // Creating a transaction with null freelancer
    function test_createTransactionNullClient() public {
        uint256 amount = randomAmount();
        startHoax(client, amount);
        vm.expectRevert(NerwoEscrow.NullAddress.selector);
        escrow.createTransaction{value: amount}(NATIVE_TOKEN, amount, address(0));
        vm.stopPrank();
    }

    // Creating a transaction with invalid amount
    function test_createTransactionInvalidAmount() public {
        uint256 amount = 9999;
        startHoax(client, amount);
        vm.expectRevert(NerwoEscrow.InvalidAmount.selector);
        escrow.createTransaction{value: amount}(NATIVE_TOKEN, amount, freelancer);
        vm.stopPrank();
    }

    function test_createTransactionStoresActualReceivedTokenAmount() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken();
        NerwoEscrow.TokenAllow[] memory supportedTokens = new NerwoEscrow.TokenAllow[](1);
        uint256 amount = randomAmount();
        uint256 expectedReceived = amount - (amount / 10);

        supportedTokens[0] = NerwoEscrow.TokenAllow(feeToken, true);
        vm.prank(owner);
        escrow.changeWhitelist(supportedTokens);

        feeToken.mint(client, amount);
        vm.startPrank(client);
        feeToken.approve(address(escrow), amount);

        uint256 expectedTID = escrow.lastTransaction() + 1;
        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.TransactionCreated(expectedTID, client, freelancer, feeToken, expectedReceived);
        uint256 transactionID = escrow.createTransaction(feeToken, amount, freelancer);
        vm.stopPrank();

        NerwoEscrow.Transaction memory transaction = escrow.getTransaction(transactionID);
        assertEq(transaction.amount, expectedReceived);
        assertEq(feeToken.balanceOf(address(escrow)), expectedReceived);
    }

    // Creating a transaction with insufficient allowance
    function test_createTransactionInsufficentAllowance() public {
        uint256 amount = randomAmount();
        startHoax(client, amount);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(escrow), 0, amount)
        );
        escrow.createTransaction(nerwoTestToken, amount, freelancer);
        vm.stopPrank();
    }
}
