// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BlacklistToken is ERC20 {
    error Blacklisted(address account);

    mapping(address => bool) public blacklisted;

    constructor() ERC20("BlacklistToken", "BLK") {}

    function setBlacklisted(address account, bool flag) external {
        blacklisted[account] = flag;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (blacklisted[to] || blacklisted[from]) {
            revert Blacklisted(blacklisted[to] ? to : from);
        }
        super._update(from, to, value);
    }
}
