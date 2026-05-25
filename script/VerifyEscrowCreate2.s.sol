// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {NerwoTetherToken} from "@nerwo/contracts/NerwoTetherToken.sol";
import {SafeTransfer} from "@nerwo/contracts/SafeTransfer.sol";
import {IArbitrator} from "@kleros/erc-792/contracts/IArbitrator.sol";

/**
 * Read-only verification helper for CREATE2 escrow deployments.
 *
 * Validates that:
 * - the predicted CREATE2 address has code deployed
 * - deployed runtime bytecode matches NerwoEscrow runtime bytecode
 * - key constructor-configured state matches env configuration
 */
contract VerifyEscrowCreate2 is Script {
    uint256 internal constant DEFAULT_FEE_RECIPIENT_BASIS_POINT = 550;
    bytes32 internal constant DEFAULT_ESCROW_SALT = bytes32(uint256(3));
    bytes internal constant DEFAULT_EXTRA_DATA =
        hex"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003";

    error MissingArbitrator();
    error MissingTokenCapTokens();
    error MissingTokenCaps();
    error TokenCapsLengthMismatch();
    error MissingOwner();
    error MissingPlatform();
    error ContractNotDeployed(address predicted);
    error DeployedCodeMismatch(address predicted, bytes32 expectedHash, bytes32 actualHash);
    error OwnerMismatch(address expected, address actual);
    error ArbitratorMismatch(address expected, address actual);
    error MetaEvidenceMismatch(string expected, string actual);
    error ExtraDataMismatch(bytes expected, bytes actual);
    error FeeRecipientMismatch(address expected, address actual);
    error FeeBasisPointMismatch(uint256 expected, uint256 actual);
    error TokenCapMismatch(address token, uint256 expected, uint256 actual);

    struct VerifyConfig {
        address deployer;
        address owner;
        address arbitrator;
        address platform;
        uint256 feeBasisPoint;
        string metaEvidenceURI;
        bytes32 escrowSalt;
        address[] cappedTokens;
        uint256[] tokenCaps;
    }

    function run() external view returns (address escrowAddress) {
        VerifyConfig memory cfg = _loadConfig();
        address predicted = _computePredictedEscrowAddress(cfg);
        if (predicted.code.length == 0) {
            revert ContractNotDeployed(predicted);
        }

        bytes32 expectedHash = keccak256(type(NerwoEscrow).runtimeCode);
        bytes32 actualHash = predicted.codehash;
        if (actualHash != expectedHash) {
            revert DeployedCodeMismatch(predicted, expectedHash, actualHash);
        }

        NerwoEscrow escrow = NerwoEscrow(payable(predicted));
        _verifyConfiguration(escrow, cfg);

        return predicted;
    }

    function _loadConfig() internal view returns (VerifyConfig memory cfg) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        cfg.deployer = vm.addr(deployerKey);

        cfg.arbitrator = vm.envAddress("NERWO_ARBITRATOR_ADDRESS");
        if (cfg.arbitrator == address(0)) revert MissingArbitrator();

        cfg.cappedTokens = vm.envAddress("NERWO_TOKENS_WHITELIST", ",");
        if (cfg.cappedTokens.length == 0) revert MissingTokenCapTokens();
        for (uint256 i = 0; i < cfg.cappedTokens.length; i++) {
            if (cfg.cappedTokens[i] == address(0)) revert MissingTokenCapTokens();
        }
        cfg.tokenCaps = vm.envUint("NERWO_TOKEN_CAPS", ",");
        if (cfg.tokenCaps.length == 0) revert MissingTokenCaps();
        if (cfg.tokenCaps.length != cfg.cappedTokens.length) revert TokenCapsLengthMismatch();

        cfg.owner = vm.envOr("NERWO_OWNER_ADDRESS", cfg.deployer);
        if (cfg.owner == address(0)) revert MissingOwner();

        cfg.platform = vm.envOr("NERWO_PLATFORM_ADDRESS", cfg.owner);
        if (cfg.platform == address(0)) revert MissingPlatform();

        cfg.feeBasisPoint = vm.envOr("NERWO_FEE_RECIPIENT_BASISPOINT", DEFAULT_FEE_RECIPIENT_BASIS_POINT);
        cfg.metaEvidenceURI = vm.envOr("NERWO_ARBITRATOR_METAEVIDENCEURI", string(""));
        cfg.escrowSalt = vm.envOr("NERWO_ESCROW_SALT", DEFAULT_ESCROW_SALT);
    }

    function _computePredictedEscrowAddress(VerifyConfig memory cfg) internal pure returns (address) {
        bytes memory initCode = abi.encodePacked(
            type(NerwoEscrow).creationCode,
            abi.encode(cfg.deployer, cfg.arbitrator, cfg.metaEvidenceURI, cfg.platform, cfg.feeBasisPoint)
        );
        return vm.computeCreate2Address(cfg.escrowSalt, keccak256(initCode));
    }

    function _verifyConfiguration(NerwoEscrow escrow, VerifyConfig memory cfg) internal view {
        if (escrow.owner() != cfg.owner) {
            revert OwnerMismatch(cfg.owner, escrow.owner());
        }

        (, IArbitrator liveArbitrator, string memory liveMetaEvidenceURI, bytes memory liveExtraData) =
            escrow.arbitratorData();
        if (address(liveArbitrator) != cfg.arbitrator) {
            revert ArbitratorMismatch(cfg.arbitrator, address(liveArbitrator));
        }
        if (keccak256(bytes(liveMetaEvidenceURI)) != keccak256(bytes(cfg.metaEvidenceURI))) {
            revert MetaEvidenceMismatch(cfg.metaEvidenceURI, liveMetaEvidenceURI);
        }
        if (keccak256(liveExtraData) != keccak256(DEFAULT_EXTRA_DATA)) {
            revert ExtraDataMismatch(DEFAULT_EXTRA_DATA, liveExtraData);
        }

        (address liveFeeRecipient, uint16 liveFeeBasisPoint) = escrow.feeRecipientData();
        if (liveFeeRecipient != cfg.platform) {
            revert FeeRecipientMismatch(cfg.platform, liveFeeRecipient);
        }
        if (uint256(liveFeeBasisPoint) != cfg.feeBasisPoint) {
            revert FeeBasisPointMismatch(cfg.feeBasisPoint, uint256(liveFeeBasisPoint));
        }

        for (uint256 i = 0; i < cfg.cappedTokens.length; i++) {
            uint256 actual = escrow.amountCaps(NerwoTetherToken(cfg.cappedTokens[i]));
            if (actual != cfg.tokenCaps[i]) {
                revert TokenCapMismatch(cfg.cappedTokens[i], cfg.tokenCaps[i], actual);
            }
        }

        uint256 nativeCap = escrow.amountCaps(SafeTransfer.NATIVE_TOKEN);
        if (nativeCap != escrow.CAP_UNLIMITED()) {
            revert TokenCapMismatch(address(SafeTransfer.NATIVE_TOKEN), escrow.CAP_UNLIMITED(), nativeCap);
        }
    }
}
