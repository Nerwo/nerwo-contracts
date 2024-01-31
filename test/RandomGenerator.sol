// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract RandomGenerator {
    error InvalidRange();

    uint256 public seed = 1;

    function srand(uint256 _seed) public {
        seed = _seed;
    }

    function random() public returns (uint256) {
        unchecked {
            seed = uint256(keccak256(abi.encodePacked(seed, block.timestamp, block.prevrandao)));
            return seed ^ ((seed >> 33) * (seed ^ (seed << 17)));
        }
    }

    function randrange(uint256 min, uint256 max) public returns (uint256) {
        if (max <= min) {
            revert InvalidRange();
        }
        uint256 randomValue = random();
        return (randomValue % (max - min + 1)) + min;
    }
}
