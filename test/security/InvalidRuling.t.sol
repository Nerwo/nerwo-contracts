// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {NerwoTetherToken} from "@nerwo/contracts/NerwoTetherToken.sol";
import {SafeTransfer} from "@nerwo/contracts/SafeTransfer.sol";

import {MaliciousArbitratorProxy} from "@nerwo/test/security/helpers/MaliciousArbitratorProxy.sol";

/**
 * @notice PoC for finding C3: an arbitrator that returns a ruling > 2 must not
 *         freeze the transaction. Post-fix the unknown ruling is treated as a
 *         50/50 split.
 */
contract InvalidRulingTest is Test {
    IERC20 internal constant NATIVE_TOKEN = IERC20(address(0));
    uint256 internal constant ARBITRATION_PRICE = 0.02 ether;
    uint256 internal constant FEE_BASIS_POINT = 500;

    address internal owner;
    address internal client;
    address internal freelancer;
    address internal feeRecipient;

    NerwoEscrow internal escrow;
    MaliciousArbitratorProxy internal proxy;
    NerwoTetherToken internal token;

    function setUp() public {
        owner = makeAddr("owner");
        client = makeAddr("client");
        freelancer = makeAddr("freelancer");
        feeRecipient = makeAddr("feeRecipient");

        token = new NerwoTetherToken();
        proxy = new MaliciousArbitratorProxy(ARBITRATION_PRICE);

        NerwoEscrow.TokenAllow[] memory supportedTokens = new NerwoEscrow.TokenAllow[](1);
        supportedTokens[0] = NerwoEscrow.TokenAllow(token, true);

        address[] memory arbitrators = new address[](2);
        arbitrators[0] = address(proxy);
        arbitrators[1] = address(proxy);

        escrow = new NerwoEscrow(owner, arbitrators, "/ipfs/test", feeRecipient, FEE_BASIS_POINT, supportedTokens);
    }

    function _createDispute(uint256 amount) internal returns (uint256 transactionID, uint256 disputeID) {
        token.mint(amount);
        assertTrue(token.transfer(client, amount));

        vm.startPrank(client);
        token.approve(address(escrow), amount);
        transactionID = escrow.createTransaction(bytes16(uint128(1)), token, amount, freelancer);
        vm.stopPrank();

        vm.deal(client, ARBITRATION_PRICE);
        vm.prank(client);
        escrow.payArbitrationFee{value: ARBITRATION_PRICE}(transactionID);

        vm.deal(freelancer, ARBITRATION_PRICE);
        vm.prank(freelancer);
        escrow.payArbitrationFee{value: ARBITRATION_PRICE}(transactionID);

        disputeID = proxy.lastDisputeID();
    }

    /* ------------------------------------------------------------ T-C3 */
    function test_C3_unknownRulingTreatedAsSplit() public {
        uint256 amount = 1e18;
        (uint256 transactionID, uint256 disputeID) = _createDispute(amount);

        // Arbitrator returns a ruling outside [0, 2] — should not lock the funds.
        proxy.setRuling(disputeID, 7);

        uint256 splitAmount = amount / 2;
        uint256 splitFee = escrow.calculateFeeRecipientAmount(splitAmount);
        uint256 splitArbitration = ARBITRATION_PRICE / 2;

        uint256 clientTokenBefore = token.balanceOf(client);
        uint256 freelancerTokenBefore = token.balanceOf(freelancer);
        uint256 feeRecipientBefore = token.balanceOf(feeRecipient);
        uint256 clientEthBefore = client.balance;
        uint256 freelancerEthBefore = freelancer.balance;

        vm.prank(client);
        escrow.acceptRuling(transactionID);

        // Both parties get half of the escrowed tokens (minus fee on the freelancer side).
        assertEq(token.balanceOf(client) - clientTokenBefore, splitAmount, "client gets half tokens");
        assertEq(
            token.balanceOf(freelancer) - freelancerTokenBefore, splitAmount - splitFee, "freelancer gets half net"
        );
        assertEq(token.balanceOf(feeRecipient) - feeRecipientBefore, splitFee, "fee recipient paid on split");

        // Both parties recover half of the arbitration deposit.
        assertEq(client.balance - clientEthBefore, splitArbitration, "client gets half arbitration");
        assertEq(freelancer.balance - freelancerEthBefore, splitArbitration, "freelancer gets half arbitration");
    }
}
