// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
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

        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, client));
        arbitrator.setArbitrationPrice(newPrice);

        vm.expectEmit(true, true, true, true, address(arbitrator));
        emit NerwoCentralizedArbitrator.ArbitrationPriceChanged(previousPrice, newPrice);

        vm.prank(court);
        arbitrator.setArbitrationPrice(newPrice);
        assertEq(arbitrator.arbitrationCost(""), newPrice);
    }
}
