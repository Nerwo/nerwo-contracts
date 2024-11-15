// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";

import {NerwoEscrow} from "../../src/NerwoEscrow.sol";

import {NerwoTest} from "../NerwoTest.sol";

contract NerwoEscrowTest is NerwoTest {
    function test_changeWhiteList() public {
        NerwoEscrow.TokenAllow[] memory whitelist = new NerwoEscrow.TokenAllow[](1);
        whitelist[0] = NerwoEscrow.TokenAllow(nerwoTestToken, true);

        vm.startPrank(owner);
        escrow.changeWhitelist(whitelist);
        vm.stopPrank();
    }

    function test_changeWhiteListUnauthorized() public {
        NerwoEscrow.TokenAllow[] memory whitelist = new NerwoEscrow.TokenAllow[](1);
        whitelist[0] = NerwoEscrow.TokenAllow(nerwoTestToken, true);

        vm.startPrank(client);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(client)));
        escrow.changeWhitelist(whitelist);
        vm.stopPrank();
    }
}
