// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NerwoTetherToken} from "@nerwo/contracts/NerwoTetherToken.sol";
import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {RandomGenerator} from "@nerwo/test/RandomGenerator.sol";

contract NerwoTest is Test {
    IERC20 internal constant NATIVE_TOKEN = IERC20(address(0));

    address internal owner;
    address internal client;
    address internal freelancer;
    address internal feeRecipient;
    RandomGenerator internal random;
    NerwoEscrow internal escrow;
    NerwoTetherToken internal nerwoTestToken;

    function setUp() public {
        owner = makeAddr("owner");
        client = makeAddr("client");
        freelancer = makeAddr("freelancer");
        feeRecipient = makeAddr("feeRecipent");
        random = new RandomGenerator();
        random.srand(vm.unixTime());

        NerwoEscrow.TokenAllow[] memory supportedTokens = new NerwoEscrow.TokenAllow[](1);
        address[] memory arbitrators = new address[](2);

        nerwoTestToken = new NerwoTetherToken();
        supportedTokens[0] = NerwoEscrow.TokenAllow(nerwoTestToken, true);

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
}
