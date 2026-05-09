// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {NerwoCentralizedArbitrator} from "@nerwo/contracts/NerwoCentralizedArbitrator.sol";
import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";
import {NerwoTetherToken} from "@nerwo/contracts/NerwoTetherToken.sol";

contract EchidnaFreelancer {
    function reimburse(NerwoEscrow escrow, uint256 transactionID) external {
        escrow.reimburse(transactionID);
    }
}

contract EchidnaRejectETH {
    receive() external payable {
        revert("ETH rejected");
    }
}

contract NerwoEscrowEchidna {
    IERC20 internal constant NATIVE_TOKEN = IERC20(address(0));
    uint256 internal constant MIN_AMOUNT = 10_000;
    uint256 internal constant MAX_AMOUNT = 1e24;
    uint256 internal constant FEE_BASIS_POINT = 500;
    uint256 internal constant MULTIPLIER_DIVISOR = 10_000;

    NerwoEscrow public escrow;
    NerwoCentralizedArbitrator public arbitrator;
    NerwoTetherToken public token;
    EchidnaFreelancer public freelancer;
    EchidnaRejectETH public rejectingFreelancer;

    uint256[] internal tokenTransactions;
    uint256[] internal nativeTransactions;
    mapping(uint256 => uint256) internal tokenOpenAmount;
    mapping(uint256 => uint256) internal nativeOpenAmount;
    uint256 public trackedOpenTokenAmount;
    uint256 public trackedOpenNativeAmount;
    uint256 public trackedPendingNativeAmount;

    constructor() payable {
        token = new NerwoTetherToken();
        arbitrator = new NerwoCentralizedArbitrator(address(this), 0.02 ether);
        freelancer = new EchidnaFreelancer();
        rejectingFreelancer = new EchidnaRejectETH();

        NerwoEscrow.TokenAllow[] memory supportedTokens = new NerwoEscrow.TokenAllow[](1);
        address[] memory arbitrators = new address[](2);
        supportedTokens[0] = NerwoEscrow.TokenAllow(token, true);
        arbitrators[0] = address(arbitrator);
        arbitrators[1] = address(arbitrator);

        escrow = new NerwoEscrow(
            address(this), arbitrators, "/ipfs/echidna", address(0xBEEF), FEE_BASIS_POINT, supportedTokens
        );
    }

    receive() external payable {}

    function createTokenTransaction(uint256 amount) external {
        amount = _normalizeAmount(amount);
        token.mint(amount);
        token.approve(address(escrow), amount);

        try escrow.createTransaction(token, amount, address(freelancer)) returns (uint256 transactionID) {
            tokenTransactions.push(transactionID);
            tokenOpenAmount[transactionID] = amount;
            trackedOpenTokenAmount += amount;
        } catch {}
    }

    function payLastTokenTransaction() external {
        uint256 transactionID = _lastTokenTransaction();
        uint256 amount = tokenOpenAmount[transactionID];
        if (amount == 0) {
            return;
        }

        try escrow.pay(transactionID) {
            tokenOpenAmount[transactionID] = 0;
            trackedOpenTokenAmount -= amount;
        } catch {}
    }

    function reimburseLastTokenTransaction() external {
        uint256 transactionID = _lastTokenTransaction();
        uint256 amount = tokenOpenAmount[transactionID];
        if (amount == 0) {
            return;
        }

        try freelancer.reimburse(escrow, transactionID) {
            tokenOpenAmount[transactionID] = 0;
            trackedOpenTokenAmount -= amount;
        } catch {}
    }

    function createNativeTransaction() external payable {
        if (msg.value < MIN_AMOUNT) {
            return;
        }

        try escrow.createTransaction{value: msg.value}(NATIVE_TOKEN, msg.value, address(rejectingFreelancer)) returns (
            uint256 transactionID
        ) {
            nativeTransactions.push(transactionID);
            nativeOpenAmount[transactionID] = msg.value;
            trackedOpenNativeAmount += msg.value;
        } catch {}
    }

    function payLastNativeTransaction() external {
        uint256 transactionID = _lastNativeTransaction();
        uint256 amount = nativeOpenAmount[transactionID];
        if (amount == 0) {
            return;
        }

        try escrow.pay(transactionID) {
            uint256 feeAmount = (amount * FEE_BASIS_POINT) / MULTIPLIER_DIVISOR;
            nativeOpenAmount[transactionID] = 0;
            trackedOpenNativeAmount -= amount;
            trackedPendingNativeAmount += amount - feeAmount;
        } catch {}
    }

    function echidna_escrow_covers_open_token_amounts() external view returns (bool) {
        return token.balanceOf(address(escrow)) >= trackedOpenTokenAmount;
    }

    function echidna_escrow_covers_open_and_pending_native_amounts() external view returns (bool) {
        return address(escrow).balance >= trackedOpenNativeAmount + trackedPendingNativeAmount;
    }

    function echidna_last_transaction_monotonic() external view returns (bool) {
        return escrow.lastTransaction() >= tokenTransactions.length + nativeTransactions.length;
    }

    function _normalizeAmount(uint256 amount) internal pure returns (uint256) {
        return MIN_AMOUNT + (amount % MAX_AMOUNT);
    }

    function _lastTokenTransaction() internal view returns (uint256) {
        if (tokenTransactions.length == 0) {
            return 0;
        }
        return tokenTransactions[tokenTransactions.length - 1];
    }

    function _lastNativeTransaction() internal view returns (uint256) {
        if (nativeTransactions.length == 0) {
            return 0;
        }
        return nativeTransactions[nativeTransactions.length - 1];
    }
}
