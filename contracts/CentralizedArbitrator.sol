/**
 *  @authors: [@clesaege, @openzeppelin, @sherpya]
 *  @reviewers: []
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 */

pragma solidity ^0.4.24;

import {CappedMath} from "./kleros/CappedMath.sol";
import {Arbitrable} from "./kleros/Arbitrable.sol";
import {AutoAppealableArbitrator} from "./kleros/AutoAppealableArbitrator.sol";

/** @title Centralized Arbitrator
 *  @dev This is a centralized arbitrator which either gives direct rulings
 */
contract CentralizedArbitrator is AutoAppealableArbitrator {
    using CappedMath for uint; // Operations bounded between 0 and 2**256 - 1.

    /** @dev Constructor. Set the initial arbitration price.
     *  @param _arbitrationPrice Amount to be paid for arbitration.
     */
    constructor(uint _arbitrationPrice) public AutoAppealableArbitrator(_arbitrationPrice) {
        _transferOwnership(msg.sender);
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal {
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}
