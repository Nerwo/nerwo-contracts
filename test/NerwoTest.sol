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
    uint256 internal constant NATIVE_TOKEN_CAP = 5 ether;
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
    uint128 internal nextOfferNonce = 1;

    function setUp() public {
        owner = makeAddr("owner");
        client = makeAddr("client");
        freelancer = makeAddr("freelancer");
        feeRecipient = makeAddr("feeRecipent");
        court = makeAddr("court");
        random = new RandomGenerator();
        random.srand(vm.unixTime());

        nerwoTestToken = new NerwoTetherToken();
        arbitrator = new NerwoCentralizedArbitrator(court, ARBITRATION_PRICE);

        escrow = new NerwoEscrow(
            owner, // newOwner
            address(arbitrator), // arbitrator
            "/ipfs/something", // metaEvidenceURI
            feeRecipient, // feeRecipient
            500 // feeRecipientBasisPoint
        );
        vm.prank(owner);
        escrow.changeTokenCap(nerwoTestToken, type(uint256).max);
        vm.prank(owner);
        escrow.changeTokenCap(NATIVE_TOKEN, NATIVE_TOKEN_CAP);
    }

    function randomAmount() internal returns (uint256) {
        return random.randrange(1e17, 1e18);
    }

    function nextOfferID() internal returns (bytes16 offerID) {
        offerID = bytes16(nextOfferNonce++);
    }

    function createTransaction(address from, address to, IERC20 token, uint256 amount)
        internal
        returns (uint256 transactionID)
    {
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
        bytes16 offerID = nextOfferID();
        vm.expectEmit(true, true, true, true, address(escrow));
        emit NerwoEscrow.TransactionCreated(offerID, expectedTID, from, to, testToken, amount);
        transactionID = escrow.createTransaction{value: value}(offerID, testToken, amount, to);

        vm.stopPrank();
    }

    function createDispute(IERC20 token) internal returns (uint256 transactionID, uint256 disputeID, uint256 amount) {
        amount = randomAmount();
        transactionID = createTransaction(client, freelancer, token, amount);
        disputeID = payArbitrationFees(transactionID, client, freelancer);
    }

    function payArbitrationFees(uint256 transactionID, address firstPayer, address secondPayer)
        internal
        returns (uint256 disputeID)
    {
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

    function assertTokenBalanceIncrease(IERC20 token, address account, uint256 magnitude, uint256 balanceBefore)
        internal
        view
    {
        assertEq(token.balanceOf(account) - balanceBefore, magnitude);
    }

    function assertTokenBalanceDecrease(IERC20 token, address account, uint256 magnitude, uint256 balanceBefore)
        internal
        view
    {
        assertEq(balanceBefore - token.balanceOf(account), magnitude);
    }

    function assertEthBalanceIncrease(address account, uint256 magnitude, uint256 balanceBefore) internal view {
        assertEq(account.balance - balanceBefore, magnitude);
    }

    function assertEthBalanceDecrease(address account, uint256 magnitude, uint256 balanceBefore) internal view {
        assertEq(balanceBefore - account.balance, magnitude);
    }
}
