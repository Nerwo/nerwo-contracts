// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {NerwoTetherToken} from "@nerwo/contracts/NerwoTetherToken.sol";

/**
 * Mainnet-friendly deploy: only NerwoEscrow.
 *
 * Refuses to run unless the arbitrator + at least one capped token are
 * provided via env. Never deploys an arbitrator or a test ERC20 — both
 * must already exist on-chain.
 */
contract DeployEscrow is Script {
    uint256 internal constant DEFAULT_FEE_RECIPIENT_BASIS_POINT = 550;
    bytes32 internal constant DEFAULT_ESCROW_SALT = bytes32(uint256(3));

    error MissingArbitrator();
    error MissingTokenCapTokens();
    error MissingTokenCaps();
    error TokenCapsLengthMismatch();
    error MissingOwner();
    error MissingPlatform();

    function run() external returns (NerwoEscrow escrow) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address arbitrator = vm.envAddress("NERWO_ARBITRATOR_ADDRESS");
        if (arbitrator == address(0)) revert MissingArbitrator();

        address[] memory cappedTokens = vm.envAddress("NERWO_TOKENS_WHITELIST", ",");
        if (cappedTokens.length == 0) revert MissingTokenCapTokens();
        for (uint256 i = 0; i < cappedTokens.length; i++) {
            if (cappedTokens[i] == address(0)) revert MissingTokenCapTokens();
        }
        uint256[] memory tokenCaps = vm.envUint("NERWO_TOKEN_CAPS", ",");
        if (tokenCaps.length == 0) revert MissingTokenCaps();
        if (tokenCaps.length != cappedTokens.length) revert TokenCapsLengthMismatch();

        address owner = vm.envOr("NERWO_OWNER_ADDRESS", deployer);
        if (owner == address(0)) revert MissingOwner();

        address platform = vm.envOr("NERWO_PLATFORM_ADDRESS", owner);
        if (platform == address(0)) revert MissingPlatform();

        uint256 feeBasisPoint = vm.envOr("NERWO_FEE_RECIPIENT_BASISPOINT", DEFAULT_FEE_RECIPIENT_BASIS_POINT);
        string memory metaEvidenceURI = vm.envOr("NERWO_ARBITRATOR_METAEVIDENCEURI", string(""));
        bool useCreate2 = vm.envOr("NERWO_USE_CREATE2", false);
        bytes32 escrowSalt = vm.envOr("NERWO_ESCROW_SALT", DEFAULT_ESCROW_SALT);

        vm.startBroadcast(deployerKey);
        if (useCreate2) {
            escrow = new NerwoEscrow{salt: escrowSalt}(deployer, arbitrator, metaEvidenceURI, platform, feeBasisPoint);
        } else {
            escrow = new NerwoEscrow(deployer, arbitrator, metaEvidenceURI, platform, feeBasisPoint);
        }

        for (uint256 i = 0; i < cappedTokens.length; i++) {
            escrow.changeTokenCap(NerwoTetherToken(cappedTokens[i]), tokenCaps[i]);
        }

        if (owner != deployer) {
            escrow.transferOwnership(owner);
        }
        vm.stopBroadcast();
    }
}
