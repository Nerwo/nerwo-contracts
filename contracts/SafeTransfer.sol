// SPDX-License-Identifier: MIT
/**
 *  @title SafeTransfer
 *  @author: [@sherpya]
 */

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library SafeTransfer {
    error TransferFailed(address recipient, address token, uint256 amount, bytes data);

    /** @dev To be emitted if a transfer to a party fails
     *  @param recipient The target of the failed operation
     *  @param token The token address
     *  @param amount The amount
     *  @param data Failed call data
     */
    event SendFailed(address indexed recipient, address indexed token, uint256 amount, bytes data);

    /** @dev Send to recipent, emit a log when fails
     *  @param target To address to send to
     *  @param amount Transaction amount
     */
    function sendTo(address target, uint256 amount) internal {
        (bool success, bytes memory data) = payable(target).call{value: amount}("");
        if (!success) {
            emit SendFailed(target, address(0), amount, data);
        }
    }

    /** @dev Send to recipent, reverts on failure
     *  @param target To address to send to
     *  @param amount Transaction amount
     */
    function transferTo(address payable target, uint256 amount) internal {
        (bool success, bytes memory data) = target.call{value: amount}("");
        if (!success) {
            revert TransferFailed(target, address(0), amount, data);
        }
    }

    /**
     * @dev Transfers token to a specified address
     * @param to The address to transfer to.
     * @param token The address of the token contract.
     * @param amount The amount to be transferred.
     */
    function _safeTransferToken(
        address to,
        IERC20 token,
        uint256 amount
    ) internal returns (bool success, bytes memory data) {
        // solhint-disable-next-line avoid-low-level-calls
        (success, data) = address(token).call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));

        if (success && data.length > 0) {
            success = abi.decode(data, (bool));
        }
    }

    /** @dev Send to recipent, emit a log when fails
     *  @param to To address to send to
     *  @param token The token address
     *  @param amount Transaction amount
     */
    function sendToken(address to, IERC20 token, uint256 amount) internal {
        (bool success, bytes memory data) = _safeTransferToken(to, token, amount);
        if (!success) {
            emit SendFailed(to, address(token), amount, data);
        }
    }

    /** @dev Send to recipent, reverts on failure
     *  @param to To address to send to
     *  @param token The token address
     *  @param amount Transaction amount
     */
    function transferToken(address to, IERC20 token, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        (bool success, bytes memory data) = _safeTransferToken(to, token, amount);
        if (!success) {
            revert TransferFailed(to, address(token), amount, data);
        }
    }
}
