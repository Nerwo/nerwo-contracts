// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * Created on 2023-03-12
 *
 * @title Claimable test token
 * @author Gianluigi Tiesi <sherpya@gmail.com>
 */

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract ClaimableToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function claim(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}
