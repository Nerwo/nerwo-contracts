// SPDX-License-Identifier: MIT
/**
 *  @title SafeTransfer
 *  @author: [@sherpya]
 */

pragma solidity ^0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library SafeTransfer {
    IERC20 private constant NATIVE_TOKEN = IERC20(address(0));

    error TransferFailed(address recipient, IERC20 token, uint256 amount);

    /** @dev To be emitted if a transfer to a party fails.
     *  @param recipient The target of the failed operation.
     *  @param token The token address.
     *  @param amount The amount.
     */
    event SendFailed(address indexed recipient, IERC20 indexed token, uint256 amount);

    /** @dev Send amount to recipent, emit a log when fails.
     *  @param to To address to send to.
     *  @param amount Transaction amount.
     *  @param revertOnError Whether the operation should revert on error.
     */
    function sendTo(address to, uint256 amount, bool revertOnError) internal {
        bool success;

        /// @solidity memory-safe-assembly
        assembly {
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        if (success) {
            return;
        }

        if (revertOnError) {
            revert TransferFailed(to, NATIVE_TOKEN, amount);
        }

        emit SendFailed(to, NATIVE_TOKEN, amount);
    }

    /** @dev Send tokens to recipent, emit a log when fails.
     *  @param to To address to send to.
     *  @param token The token address.
     *  @param amount The amount to be transferred.
     *  @param revertOnError Whether the operation should revert on error.
     */
    function sendToken(address to, IERC20 token, uint256 amount, bool revertOnError) internal {
        if (token == NATIVE_TOKEN) {
            return sendTo(to, amount, revertOnError);
        }

        bytes memory data;
        bool success;

        // solhint-disable-next-line avoid-low-level-calls
        (success, data) = address(token).call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));

        if (success && data.length > 0) {
            success = abi.decode(data, (bool));
        }

        if (success) {
            return;
        }

        if (revertOnError) {
            revert TransferFailed(to, token, amount);
        }

        emit SendFailed(to, token, amount);
    }
}
