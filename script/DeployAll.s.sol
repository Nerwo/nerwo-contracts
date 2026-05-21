// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {NerwoCentralizedArbitrator} from "@nerwo/contracts/NerwoCentralizedArbitrator.sol";
import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {NerwoTetherToken} from "@nerwo/contracts/NerwoTetherToken.sol";

contract DeployAll is Script {
    uint256 internal constant DEFAULT_ARBITRATION_PRICE = 0.02 ether;
    uint256 internal constant DEFAULT_FEE_RECIPIENT_BASIS_POINT = 550;
    uint256 internal constant DEFAULT_TEST_TOKEN_CAP = 5_000 * 10 ** 6;
    bytes32 internal constant DEFAULT_ARBITRATOR_SALT = bytes32(uint256(1));
    bytes32 internal constant DEFAULT_TEST_TOKEN_SALT = bytes32(uint256(2));
    bytes32 internal constant DEFAULT_ESCROW_SALT = bytes32(uint256(3));

    struct DeployConfig {
        address owner;
        address court;
        address platform;
        uint256 arbitrationPrice;
        uint256 feeBasisPoint;
        string metaEvidenceURI;
        address existingArbitrator;
        address existingProxy;
        bool useCreate2;
        bytes32 arbitratorSalt;
        bytes32 testTokenSalt;
        bytes32 escrowSalt;
    }

    error ExistingCreate2CodeMismatch(address target, bytes32 expectedHash, bytes32 actualHash);
    error TokenCapsLengthMismatch();

    function run()
        external
        returns (NerwoCentralizedArbitrator arbitrator, NerwoTetherToken testToken, NerwoEscrow escrow)
    {
        uint256 deployerKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(deployerKey);
        DeployConfig memory cfg = _loadConfig(deployer);
        address[] memory cappedTokens = _cappedTokens();
        uint256[] memory tokenCaps = _tokenCaps();
        if (cappedTokens.length != 0 && tokenCaps.length != cappedTokens.length) {
            revert TokenCapsLengthMismatch();
        }

        vm.startBroadcast(deployerKey);

        if (cfg.existingArbitrator == address(0) || cfg.existingProxy == address(0)) {
            arbitrator = _deployArbitrator(cfg.court, cfg.arbitrationPrice, cfg.useCreate2, cfg.arbitratorSalt);
            cfg.existingArbitrator = address(arbitrator);
            cfg.existingProxy = address(arbitrator);
        } else {
            arbitrator = NerwoCentralizedArbitrator(cfg.existingArbitrator);
        }

        if (cappedTokens.length == 0) {
            testToken = _deployTestToken(cfg.useCreate2, cfg.testTokenSalt);
            cappedTokens = new address[](1);
            cappedTokens[0] = address(testToken);
            tokenCaps = new uint256[](1);
            tokenCaps[0] = DEFAULT_TEST_TOKEN_CAP;
        }

        address[] memory arbitrators = new address[](2);
        arbitrators[0] = cfg.existingArbitrator;
        arbitrators[1] = cfg.existingProxy;

        escrow = _deployEscrow(
            deployer,
            arbitrators,
            cfg.metaEvidenceURI,
            cfg.platform,
            cfg.feeBasisPoint,
            cfg.useCreate2,
            cfg.escrowSalt
        );

        for (uint256 i = 0; i < cappedTokens.length; i++) {
            escrow.changeTokenCap(NerwoTetherToken(cappedTokens[i]), tokenCaps[i]);
        }

        if (cfg.owner != deployer && escrow.owner() == deployer) {
            escrow.transferOwnership(cfg.owner);
        }

        vm.stopBroadcast();
    }

    function _deployArbitrator(address court, uint256 arbitrationPrice, bool useCreate2, bytes32 salt)
        internal
        returns (NerwoCentralizedArbitrator)
    {
        if (!useCreate2) {
            return new NerwoCentralizedArbitrator(court, arbitrationPrice);
        }

        bytes memory initCode = abi.encodePacked(type(NerwoCentralizedArbitrator).creationCode, abi.encode(court, arbitrationPrice));
        address predicted = vm.computeCreate2Address(salt, keccak256(initCode));
        if (predicted.code.length != 0) {
            return NerwoCentralizedArbitrator(predicted);
        }
        return new NerwoCentralizedArbitrator{salt: salt}(court, arbitrationPrice);
    }

    function _deployTestToken(bool useCreate2, bytes32 salt) internal returns (NerwoTetherToken) {
        if (!useCreate2) {
            return new NerwoTetherToken();
        }

        bytes memory initCode = type(NerwoTetherToken).creationCode;
        address predicted = vm.computeCreate2Address(salt, keccak256(initCode));
        bytes32 expectedHash = keccak256(type(NerwoTetherToken).runtimeCode);
        _assertOrEmptyCode(predicted, expectedHash);

        if (predicted.code.length != 0) {
            return NerwoTetherToken(predicted);
        }
        return new NerwoTetherToken{salt: salt}();
    }

    function _deployEscrow(
        address owner,
        address[] memory arbitrators,
        string memory metaEvidenceURI,
        address platform,
        uint256 feeBasisPoint,
        bool useCreate2,
        bytes32 salt
    ) internal returns (NerwoEscrow) {
        if (!useCreate2) {
            return new NerwoEscrow(owner, arbitrators, metaEvidenceURI, platform, feeBasisPoint);
        }

        bytes memory initCode = abi.encodePacked(
            type(NerwoEscrow).creationCode, abi.encode(owner, arbitrators, metaEvidenceURI, platform, feeBasisPoint)
        );
        address predicted = vm.computeCreate2Address(salt, keccak256(initCode));
        bytes32 expectedHash = keccak256(type(NerwoEscrow).runtimeCode);
        _assertOrEmptyCode(predicted, expectedHash);

        if (predicted.code.length != 0) {
            return NerwoEscrow(payable(predicted));
        }
        return new NerwoEscrow{salt: salt}(owner, arbitrators, metaEvidenceURI, platform, feeBasisPoint);
    }

    function _cappedTokens() internal view returns (address[] memory tokens) {
        address[] memory empty;
        return vm.envOr("NERWO_TOKENS_WHITELIST", ",", empty);
    }

    function _tokenCaps() internal view returns (uint256[] memory caps) {
        uint256[] memory empty;
        return vm.envOr("NERWO_TOKEN_CAPS", ",", empty);
    }

    function _loadConfig(address deployer) internal view returns (DeployConfig memory cfg) {
        cfg.owner = vm.envOr("NERWO_OWNER_ADDRESS", deployer);
        cfg.court = vm.envOr("NERWO_COURT_ADDRESS", cfg.owner);
        cfg.platform = vm.envOr("NERWO_PLATFORM_ADDRESS", cfg.owner);
        cfg.arbitrationPrice = vm.envOr("NERWO_ARBITRATION_PRICE_WEI", DEFAULT_ARBITRATION_PRICE);
        cfg.feeBasisPoint = vm.envOr("NERWO_FEE_RECIPIENT_BASISPOINT", DEFAULT_FEE_RECIPIENT_BASIS_POINT);
        cfg.metaEvidenceURI = vm.envOr("NERWO_ARBITRATOR_METAEVIDENCEURI", string(""));
        cfg.existingArbitrator = vm.envOr("NERWO_ARBITRATOR_ADDRESS", address(0));
        cfg.existingProxy = vm.envOr("NERWO_ARBITRATORPROXY_ADDRESS", address(0));
        cfg.useCreate2 = vm.envOr("NERWO_USE_CREATE2", false);
        cfg.arbitratorSalt = vm.envOr("NERWO_ARBITRATOR_SALT", DEFAULT_ARBITRATOR_SALT);
        cfg.testTokenSalt = vm.envOr("NERWO_TEST_TOKEN_SALT", DEFAULT_TEST_TOKEN_SALT);
        cfg.escrowSalt = vm.envOr("NERWO_ESCROW_SALT", DEFAULT_ESCROW_SALT);
    }

    function _assertOrEmptyCode(address target, bytes32 expectedHash) internal view {
        if (target.code.length == 0) {
            return;
        }

        bytes32 actualHash = target.codehash;
        if (actualHash != expectedHash) {
            revert ExistingCreate2CodeMismatch(target, expectedHash, actualHash);
        }
    }
}
