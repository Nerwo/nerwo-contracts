// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {NerwoEscrow} from "../src/NerwoEscrow.sol";

contract NerwoEscrowScript is Script {
    NerwoEscrow public nerwoEscrow;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        NerwoEscrow.TokenAllow[] memory whitelist;
        address[] memory arbitrators = new address[](2);

        nerwoEscrow = new NerwoEscrow(address(0), arbitrators, "", address(0), 0, whitelist);

        vm.stopBroadcast();
    }
}
