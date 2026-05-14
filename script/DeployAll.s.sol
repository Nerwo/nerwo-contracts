// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {NerwoCentralizedArbitrator} from "@nerwo/contracts/NerwoCentralizedArbitrator.sol";
import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {NerwoTetherToken} from "@nerwo/contracts/NerwoTetherToken.sol";

contract DeployAll is Script {
    uint256 internal constant DEFAULT_ARBITRATION_PRICE = 0.02 ether;
    uint256 internal constant DEFAULT_FEE_RECIPIENT_BASIS_POINT = 550;
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

    function run()
        external
        returns (NerwoCentralizedArbitrator arbitrator, NerwoTetherToken testToken, NerwoEscrow escrow)
    {
        uint256 deployerKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        DeployConfig memory cfg = _loadConfig(vm.addr(deployerKey));
        address[] memory whitelistedTokens = _whitelistedTokens();

        vm.startBroadcast(deployerKey);

        if (cfg.existingArbitrator == address(0) || cfg.existingProxy == address(0)) {
            arbitrator = _deployArbitrator(cfg.court, cfg.arbitrationPrice, cfg.useCreate2, cfg.arbitratorSalt);
            cfg.existingArbitrator = address(arbitrator);
            cfg.existingProxy = address(arbitrator);
        } else {
            arbitrator = NerwoCentralizedArbitrator(cfg.existingArbitrator);
        }

        if (whitelistedTokens.length == 0) {
            testToken = _deployTestToken(cfg.useCreate2, cfg.testTokenSalt);
            whitelistedTokens = new address[](1);
            whitelistedTokens[0] = address(testToken);
        }

        address[] memory arbitrators = new address[](2);
        arbitrators[0] = cfg.existingArbitrator;
        arbitrators[1] = cfg.existingProxy;

        NerwoEscrow.TokenAllow[] memory supportedTokens = new NerwoEscrow.TokenAllow[](whitelistedTokens.length);
        for (uint256 i = 0; i < whitelistedTokens.length; i++) {
            supportedTokens[i] = NerwoEscrow.TokenAllow({token: NerwoTetherToken(whitelistedTokens[i]), allow: true});
        }

        escrow = _deployEscrow(
            cfg.owner,
            arbitrators,
            cfg.metaEvidenceURI,
            cfg.platform,
            cfg.feeBasisPoint,
            supportedTokens,
            cfg.useCreate2,
            cfg.escrowSalt
        );

        vm.stopBroadcast();
    }

    function _deployArbitrator(address court, uint256 arbitrationPrice, bool useCreate2, bytes32 salt)
        internal
        returns (NerwoCentralizedArbitrator)
    {
        if (useCreate2) {
            return new NerwoCentralizedArbitrator{salt: salt}(court, arbitrationPrice);
        }
        return new NerwoCentralizedArbitrator(court, arbitrationPrice);
    }

    function _deployTestToken(bool useCreate2, bytes32 salt) internal returns (NerwoTetherToken) {
        if (useCreate2) {
            return new NerwoTetherToken{salt: salt}();
        }
        return new NerwoTetherToken();
    }

    function _deployEscrow(
        address owner,
        address[] memory arbitrators,
        string memory metaEvidenceURI,
        address platform,
        uint256 feeBasisPoint,
        NerwoEscrow.TokenAllow[] memory supportedTokens,
        bool useCreate2,
        bytes32 salt
    ) internal returns (NerwoEscrow) {
        if (useCreate2) {
            return new NerwoEscrow{salt: salt}(owner, arbitrators, metaEvidenceURI, platform, feeBasisPoint, supportedTokens);
        }
        return new NerwoEscrow(owner, arbitrators, metaEvidenceURI, platform, feeBasisPoint, supportedTokens);
    }

    function _whitelistedTokens() internal view returns (address[] memory tokens) {
        address[] memory empty;
        return vm.envOr("NERWO_TOKENS_WHITELIST", ",", empty);
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
}
