// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IArbitrator} from "@kleros/erc-792/contracts/IArbitrator.sol";
import {IArbitrable} from "@kleros/erc-792/contracts/IArbitrable.sol";

/**
 * @notice Arbitrator mock that lets tests force any ruling value, including
 *         out-of-range values (>2) to exercise InvalidRuling paths.
 */
contract MaliciousArbitrator is IArbitrator {
    uint256 public arbitrationPrice;
    uint256 public lastDisputeID;

    mapping(uint256 => uint256) public rulings;
    mapping(uint256 => bool) public ruled;
    mapping(uint256 => IArbitrable) public arbitrated;

    constructor(uint256 _price) {
        arbitrationPrice = _price;
    }

    function setRuling(uint256 _disputeID, uint256 _ruling) external {
        rulings[_disputeID] = _ruling;
        ruled[_disputeID] = true;
        arbitrated[_disputeID].rule(_disputeID, _ruling);
    }

    function arbitrationCost(bytes calldata) external view returns (uint256) {
        return arbitrationPrice;
    }

    function createDispute(uint256, bytes calldata) external payable returns (uint256 disputeID) {
        require(msg.value == arbitrationPrice, "wrong fee");
        unchecked {
            disputeID = ++lastDisputeID;
        }
        arbitrated[disputeID] = IArbitrable(msg.sender);
    }

    function appeal(uint256, bytes calldata) external payable {
        revert("no appeal");
    }

    function appealCost(uint256, bytes calldata) external pure returns (uint256) {
        return type(uint256).max;
    }

    function appealPeriod(uint256) external pure returns (uint256, uint256) {
        return (0, 0);
    }

    function disputeStatus(uint256 _disputeID) external view returns (DisputeStatus) {
        return ruled[_disputeID] ? DisputeStatus.Solved : DisputeStatus.Waiting;
    }

    function currentRuling(uint256 _disputeID) external view returns (uint256) {
        return rulings[_disputeID];
    }
}
