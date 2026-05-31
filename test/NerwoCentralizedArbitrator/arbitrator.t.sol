// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {NerwoCentralizedArbitrator} from "@nerwo/contracts/NerwoCentralizedArbitrator.sol";
import {NerwoTest} from "@nerwo/test/NerwoTest.sol";

contract NerwoCentralizedArbitratorTest is NerwoTest {
    function test_createDisputeInsufficientPayment() public {
        vm.prank(client);
        vm.expectRevert(NerwoCentralizedArbitrator.InsufficientPayment.selector);
        arbitrator.createDispute(2, bytes(""));
    }

    function test_setArbitrationPrice() public {
        uint256 newPrice = 0.005 ether;
        uint256 previousPrice = arbitrator.arbitrationCost("");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, client, arbitrator.ADMIN_ROLE()
            )
        );
        vm.prank(client);
        arbitrator.setArbitrationPrice(newPrice);

        vm.expectEmit(true, true, true, true, address(arbitrator));
        emit NerwoCentralizedArbitrator.ArbitrationPriceChanged(previousPrice, newPrice);

        vm.prank(court);
        arbitrator.setArbitrationPrice(newPrice);
        assertEq(arbitrator.arbitrationCost(""), newPrice);
    }
}
