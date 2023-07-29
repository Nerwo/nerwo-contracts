// SPDX-License-Identifier: MIT
/**
 *  @title SafeTransfer
 *  @author: [@sherpya]
 */

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library SafeTransfer {
    error TransferFailed(address recipient, IERC20 token, uint256 amount);

    /** @dev To be emitted if a transfer to a party fails.
     *  @param recipient The target of the failed operation.
     *  @param token The token address.
     *  @param amount The amount.
     */
    event SendFailed(address indexed recipient, address indexed token, uint256 amount);

    /** @dev Send amount to recipent, emit a log when fails.
     *  @param target To address to send to.
     *  @param amount Transaction amount.
     */
    function sendTo(address target, uint256 amount) internal {
        (bool success, ) = target.call{value: amount}("");
        if (!success) {
            emit SendFailed(target, address(0), amount);
        }
    }

    /** @dev Send amount to recipent, reverts on failure.
     *  @param target To address to send to.
     *  @param amount Transaction amount.
     */
    function transferTo(address target, uint256 amount) internal {
        (bool success, ) = target.call{value: amount}("");
        if (!success) {
            revert TransferFailed(target, IERC20(address(0)), amount);
        }
    }

    /**
     * @dev Transfers tokens to a specified address, returns error if fails.
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

    /** @dev Send tokens to recipent, emit a log when fails.
     *  @param to To address to send to.
     *  @param token The token address.
     *  @param amount The amount to be transferred.
     */
    function sendToken(address to, IERC20 token, uint256 amount) internal {
        if (address(token) == address(0)) {
            return sendTo(to, amount);
        }

        (bool success, ) = _safeTransferToken(to, token, amount);
        if (!success) {
            emit SendFailed(to, address(token), amount);
        }
    }

    /** @dev Transfers tokens to a specified address, reverts on failure.
     *  @param to To address to send to.
     *  @param token The token address.
     *  @param amount The amount to be transferred.
     */
    function transferToken(address to, IERC20 token, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        if (address(token) == address(0)) {
            return transferTo(to, amount);
        }

        (bool success, ) = _safeTransferToken(to, token, amount);
        if (!success) {
            revert TransferFailed(to, token, amount);
        }
    }
}
