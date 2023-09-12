// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * Created on 2023-03-05
 *
 * @title USDT like test token
 * @author Gianluigi Tiesi <sherpya@gmail.com>
 */

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NerwoTetherToken is ERC20 {
    constructor() ERC20("Nerwo Test USDT", "USDT.n") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
