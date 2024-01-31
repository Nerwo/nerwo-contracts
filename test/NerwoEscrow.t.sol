// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NerwoTetherToken} from "../contracts/NerwoTetherToken.sol";
import {RandomGenerator} from "./RandomGenerator.sol";
import {NerwoEscrow} from "../contracts/NerwoEscrow.sol";

contract NerwoEscrowTest is Test {
    IERC20 private constant NATIVE_TOKEN = IERC20(address(0));

    address private owner;
    address private client;
    address private freelancer;
    address private feeRecipient;
    NerwoEscrow private escrow;
    NerwoTetherToken private testToken;
    RandomGenerator random;

    function setUp() public {
        owner = makeAddr("owner");
        client = makeAddr("client");
        freelancer = makeAddr("freelancer");
        feeRecipient = makeAddr("feeRecipent");
        random = new RandomGenerator();
        random.srand(vm.unixTime());

        NerwoEscrow.TokenAllow[] memory supportedTokens = new NerwoEscrow.TokenAllow[](1);
        address[] memory arbitrators = new address[](2);

        testToken = new NerwoTetherToken();
        supportedTokens[0] = NerwoEscrow.TokenAllow(testToken, true);

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

    function createTransaction() internal {
        uint256 amount = randomAmount();
        vm.startPrank(client);
        testToken.mint(amount);
        testToken.approve(address(escrow), amount);
        vm.expectEmit(false, true, true, true, address(escrow));
        emit NerwoEscrow.TransactionCreated(0, client, freelancer, testToken, amount);
        escrow.createTransaction(testToken, amount, freelancer);
        vm.stopPrank();
    }

    function createNativeTransaction() internal {
        uint256 amount = randomAmount();
        startHoax(client, amount);
        vm.expectEmit(false, true, true, true, address(escrow));
        emit NerwoEscrow.TransactionCreated(0, client, freelancer, NATIVE_TOKEN, amount);
        escrow.createTransaction{value: amount}(NATIVE_TOKEN, amount, freelancer);
        vm.stopPrank();
    }

    function testOne() public {
        createTransaction();
        createNativeTransaction();
    }
}
