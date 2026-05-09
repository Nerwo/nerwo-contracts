// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NerwoTetherToken} from "@nerwo/contracts/NerwoTetherToken.sol";
import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {NerwoCentralizedArbitrator} from "@nerwo/contracts/NerwoCentralizedArbitrator.sol";
import {RandomGenerator} from "@nerwo/test/RandomGenerator.sol";

contract NerwoTest is Test {
    IERC20 internal constant NATIVE_TOKEN = IERC20(address(0));
    uint256 internal constant ARBITRATION_PRICE = 0.02 ether;
    uint256 internal constant FEE_TIMEOUT = 604800;
    uint256 internal constant FEE_RECIPIENT_BASIS_POINT = 500;
    uint256 internal constant RULING_SPLIT = 0;
    uint256 internal constant RULING_CLIENT_WINS = 1;
    uint256 internal constant RULING_FREELANCER_WINS = 2;

    address internal owner;
    address internal client;
    address internal freelancer;
    address internal feeRecipient;
    address internal court;
    RandomGenerator internal random;
    NerwoEscrow internal escrow;
    NerwoCentralizedArbitrator internal arbitrator;
    NerwoTetherToken internal nerwoTestToken;

    function setUp() public {
        owner = makeAddr("owner");
        client = makeAddr("client");
        freelancer = makeAddr("freelancer");
        feeRecipient = makeAddr("feeRecipent");
        court = makeAddr("court");
        random = new RandomGenerator();
        random.srand(vm.unixTime());

        NerwoEscrow.TokenAllow[] memory supportedTokens = new NerwoEscrow.TokenAllow[](1);
        address[] memory arbitrators = new address[](2);

        nerwoTestToken = new NerwoTetherToken();
        arbitrator = new NerwoCentralizedArbitrator(court, ARBITRATION_PRICE);
        supportedTokens[0] = NerwoEscrow.TokenAllow(nerwoTestToken, true);
        arbitrators[0] = address(arbitrator);
        arbitrators[1] = address(arbitrator);

        escrow = new NerwoEscrow(
            owner, // newOwner
            arbitrators, // arbitrators
            "/ipfs/something", // metaEvidenceURI
            feeRecipient, // feeRecipient
            500, // feeRecipientBasisPoint
            supportedTokens // supportedTokens
        );
    }

    function randomAmount() internal returns (uint256) {
        return random.randrange(1e17, 1e18);
    }

    function createTransaction(
        address from,
        address to,
        IERC20 token,
        uint256 amount
    ) internal returns (uint256 transactionID) {
        uint256 value = 0;
        NerwoTetherToken testToken = NerwoTetherToken(address(token));

        vm.startPrank(from);

        if (token == NATIVE_TOKEN) {
            vm.deal(from, amount);
            value = amount;
        } else {
            testToken.mint(amount);
            testToken.approve(address(escrow), amount);
        }

        uint256 expectedTID = escrow.lastTransaction() + 1;
        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.TransactionCreated(expectedTID, from, to, testToken, amount);
        transactionID = escrow.createTransaction{value: value}(testToken, amount, to);

        vm.stopPrank();
    }

    function createDispute(IERC20 token) internal returns (uint256 transactionID, uint256 disputeID, uint256 amount) {
        amount = randomAmount();
        transactionID = createTransaction(client, freelancer, token, amount);
        disputeID = payArbitrationFees(transactionID, client, freelancer);
    }

    function payArbitrationFees(
        uint256 transactionID,
        address firstPayer,
        address secondPayer
    ) internal returns (uint256 disputeID) {
        vm.deal(firstPayer, ARBITRATION_PRICE);
        vm.prank(firstPayer);
        escrow.payArbitrationFee{value: ARBITRATION_PRICE}(transactionID);

        vm.deal(secondPayer, ARBITRATION_PRICE);
        vm.prank(secondPayer);
        escrow.payArbitrationFee{value: ARBITRATION_PRICE}(transactionID);

        disputeID = arbitrator.lastDispute();
    }

    function giveRuling(uint256 disputeID, uint256 ruling) internal {
        vm.prank(court);
        arbitrator.giveRuling(disputeID, ruling);
    }

    function assertTokenBalanceDelta(
        IERC20 token,
        address account,
        int256 expectedDelta,
        uint256 balanceBefore
    ) internal view {
        uint256 balanceAfter = token.balanceOf(account);
        if (expectedDelta < 0) {
            assertEq(balanceBefore - balanceAfter, uint256(-expectedDelta));
        } else {
            assertEq(balanceAfter - balanceBefore, uint256(expectedDelta));
        }
    }

    function assertEthBalanceDelta(address account, int256 expectedDelta, uint256 balanceBefore) internal view {
        uint256 balanceAfter = account.balance;
        if (expectedDelta < 0) {
            assertEq(balanceBefore - balanceAfter, uint256(-expectedDelta));
        } else {
            assertEq(balanceAfter - balanceBefore, uint256(expectedDelta));
        }
    }
}
