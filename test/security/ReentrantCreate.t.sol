// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {NerwoTest} from "@nerwo/test/NerwoTest.sol";

import {ReentrantToken} from "@nerwo/test/security/helpers/ReentrantToken.sol";

/**
 * @notice PoC for finding H1: createTransaction lacks nonReentrant. A token whose
 *         transferFrom calls back into the escrow can re-enter and create a second
 *         transaction within the first call. Post-fix this must revert.
 */
contract ReentrantCreateTest is NerwoTest {
    ReentrantToken internal reentrantToken;
    address internal secondFreelancer;

    function _enableReentrantToken() internal {
        reentrantToken = new ReentrantToken();
        secondFreelancer = makeAddr("secondFreelancer");

        vm.prank(owner);
        escrow.changeTokenCap(reentrantToken, type(uint256).max);
    }

    /* ------------------------------------------------------------ T-H1 */
    function test_H1_reentrantTokenCannotReenterCreateTransaction() public {
        _enableReentrantToken();

        uint256 outerAmount = 1e18;
        uint256 innerAmount = 5e17;

        reentrantToken.mint(client, outerAmount);
        vm.prank(client);
        reentrantToken.approve(address(escrow), outerAmount);

        // Token is armed to re-enter createTransaction during transferFrom.
        reentrantToken.arm(escrow, secondFreelancer, innerAmount);

        // Post-fix expectation: nonReentrant guard rejects the inner call. The
        // ReentrancyGuardReentrantCall revert is bubbled up by safeTransferFrom
        // and surfaces as the raw selector at the outer call site.
        vm.prank(client);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        escrow.createTransaction(nextOfferID(), reentrantToken, outerAmount, freelancer);
    }
}
