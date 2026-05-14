// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {NerwoTetherToken} from "@nerwo/contracts/NerwoTetherToken.sol";

/**
 * Mainnet-friendly deploy: only NerwoEscrow.
 *
 * Refuses to run unless the arbitrator + proxy + at least one
 * whitelisted token are provided via env. Never deploys an arbitrator
 * or a test ERC20 — both must already exist on-chain.
 */
contract DeployEscrow is Script {
    uint256 internal constant DEFAULT_FEE_RECIPIENT_BASIS_POINT = 550;

    error MissingArbitrator();
    error MissingArbitratorProxy();
    error MissingTokenWhitelist();
    error MissingOwner();
    error MissingPlatform();

    function run() external returns (NerwoEscrow escrow) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address arbitrator = vm.envAddress("NERWO_ARBITRATOR_ADDRESS");
        address proxy = vm.envAddress("NERWO_ARBITRATORPROXY_ADDRESS");
        if (arbitrator == address(0)) revert MissingArbitrator();
        if (proxy == address(0)) revert MissingArbitratorProxy();

        address[] memory whitelistedTokens = vm.envAddress("NERWO_TOKENS_WHITELIST", ",");
        if (whitelistedTokens.length == 0) revert MissingTokenWhitelist();
        for (uint256 i = 0; i < whitelistedTokens.length; i++) {
            if (whitelistedTokens[i] == address(0)) revert MissingTokenWhitelist();
        }

        address owner = vm.envOr("NERWO_OWNER_ADDRESS", deployer);
        if (owner == address(0)) revert MissingOwner();

        address platform = vm.envOr("NERWO_PLATFORM_ADDRESS", owner);
        if (platform == address(0)) revert MissingPlatform();

        uint256 feeBasisPoint = vm.envOr("NERWO_FEE_RECIPIENT_BASISPOINT", DEFAULT_FEE_RECIPIENT_BASIS_POINT);
        string memory metaEvidenceURI = vm.envOr("NERWO_ARBITRATOR_METAEVIDENCEURI", string(""));

        address[] memory arbitrators = new address[](2);
        arbitrators[0] = arbitrator;
        arbitrators[1] = proxy;

        NerwoEscrow.TokenAllow[] memory supportedTokens = new NerwoEscrow.TokenAllow[](whitelistedTokens.length);
        for (uint256 i = 0; i < whitelistedTokens.length; i++) {
            supportedTokens[i] = NerwoEscrow.TokenAllow({token: NerwoTetherToken(whitelistedTokens[i]), allow: true});
        }

        vm.startBroadcast(deployerKey);
        escrow = new NerwoEscrow(owner, arbitrators, metaEvidenceURI, platform, feeBasisPoint, supportedTokens);
        vm.stopBroadcast();
    }
}
