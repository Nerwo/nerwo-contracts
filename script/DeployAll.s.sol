// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {NerwoCentralizedArbitrator} from "@nerwo/contracts/NerwoCentralizedArbitrator.sol";
import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {NerwoTetherToken} from "@nerwo/contracts/NerwoTetherToken.sol";

contract DeployAll is Script {
    uint256 internal constant DEFAULT_ARBITRATION_PRICE = 0.02 ether;
    uint256 internal constant DEFAULT_FEE_RECIPIENT_BASIS_POINT = 550;

    function run()
        external
        returns (NerwoCentralizedArbitrator arbitrator, NerwoTetherToken testToken, NerwoEscrow escrow)
    {
        uint256 deployerKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(deployerKey);

        address owner = vm.envOr("NERWO_OWNER_ADDRESS", deployer);
        address court = vm.envOr("NERWO_COURT_ADDRESS", owner);
        address platform = vm.envOr("NERWO_PLATFORM_ADDRESS", owner);
        uint256 arbitrationPrice = vm.envOr("NERWO_ARBITRATION_PRICE_WEI", DEFAULT_ARBITRATION_PRICE);
        uint256 feeBasisPoint = vm.envOr("NERWO_FEE_RECIPIENT_BASISPOINT", DEFAULT_FEE_RECIPIENT_BASIS_POINT);
        string memory metaEvidenceURI = vm.envOr("NERWO_ARBITRATOR_METAEVIDENCEURI", string(""));
        address existingArbitrator = vm.envOr("NERWO_ARBITRATOR_ADDRESS", address(0));
        address existingProxy = vm.envOr("NERWO_ARBITRATORPROXY_ADDRESS", address(0));
        address[] memory whitelistedTokens = _whitelistedTokens();

        vm.startBroadcast(deployerKey);

        if (existingArbitrator == address(0) || existingProxy == address(0)) {
            arbitrator = new NerwoCentralizedArbitrator(court, arbitrationPrice);
            existingArbitrator = address(arbitrator);
            existingProxy = address(arbitrator);
        } else {
            arbitrator = NerwoCentralizedArbitrator(existingArbitrator);
        }

        if (whitelistedTokens.length == 0) {
            testToken = new NerwoTetherToken();
            whitelistedTokens = new address[](1);
            whitelistedTokens[0] = address(testToken);
        }

        address[] memory arbitrators = new address[](2);
        arbitrators[0] = existingArbitrator;
        arbitrators[1] = existingProxy;

        NerwoEscrow.TokenAllow[] memory supportedTokens = new NerwoEscrow.TokenAllow[](whitelistedTokens.length);
        for (uint256 i = 0; i < whitelistedTokens.length; i++) {
            supportedTokens[i] = NerwoEscrow.TokenAllow({token: NerwoTetherToken(whitelistedTokens[i]), allow: true});
        }

        escrow = new NerwoEscrow(owner, arbitrators, metaEvidenceURI, platform, feeBasisPoint, supportedTokens);

        vm.stopBroadcast();
    }

    function _whitelistedTokens() internal view returns (address[] memory tokens) {
        address[] memory empty;
        return vm.envOr("NERWO_TOKENS_WHITELIST", ",", empty);
    }
}
