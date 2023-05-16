// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * Created on 2023-03-05
 *
 * @title USDT like test token
 * @author Gianluigi Tiesi <sherpya@gmail.com>
 */

import {ClaimableToken} from "./ClaimableToken.sol";

contract TetherToken is ClaimableToken {
    constructor() ClaimableToken("Tether USD Like", "USDT") {}
}
