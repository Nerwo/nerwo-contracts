// SPDX-License-Identifier: MIT

/**
 *  @title NerwoCentralizedArbitrator
 *  @author @ferittuncer, @hbarcelos, @sherpya
 *
 *                         ////////                 ////////
 *                       ////////////             ////////////
 *                       /////////////            ////////////
 *                       //////////////           ////////////
 *                         /////////////            ////////
 *                              ,/////////
 *                                    /////*
 *                                       /////
 *                                         //////
 *                                           /////////,
 *                         ////////            /////////////
 *                       ////////////           //////////////
 *                      ,////////////            /////////////
 *                       ////////////             ////////////
 *                         ////////                 ////////
 *
 *  @notice This contract implement a simple not appealable Centralized Arbitrator,
 *  mainly used for test units.
 */

pragma solidity ^0.8.21;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IArbitrator} from "@kleros/erc-792/contracts/IArbitrator.sol";
import {IArbitrable} from "@kleros/erc-792/contracts/IArbitrable.sol";

import {SafeTransfer} from "./SafeTransfer.sol";

contract NerwoCentralizedArbitrator is AccessControl, ReentrancyGuard, IArbitrator {
    error InsufficientPayment();
    error InvalidRuling(uint256 _ruling, uint256 _numberOfChoices);
    error InvalidStatus(DisputeStatus _expected);

    error InvalidCaller(address expected);
    error InvalidArguments();
    error InvalidDispute();
    error AlreadyResolved();

    struct ArbitratorDispute {
        IArbitrable arbitrated;
        uint8 choices;
        uint8 ruling;
        DisputeStatus status;
    }

    uint256 public lastDispute;
    mapping(uint256 => ArbitratorDispute) private arbitratorDisputes;

    uint256 private arbitrationPrice; // Not public because arbitrationCost already acts as an accessor.
    uint256 private constant NOT_PAYABLE_VALUE = type(uint256).max; // High value to be sure that the appeal is too expensive.
    uint256 public constant MAX_NUMBER_OF_CHOICES = 2;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /**
     * @dev Emitted when the arbitration price is updated by an admin.
     * @param previousPrice The previous arbitration price.
     * @param newPrice The updated arbitration price.
     */
    event ArbitrationPriceChanged(uint256 previousPrice, uint256 newPrice);

    modifier onlyValidDispute(uint256 _disputeID) {
        if (address(arbitratorDisputes[_disputeID].arbitrated) == address(0)) {
            revert InvalidDispute();
        }
        _;
    }

    /**
     * @dev contructor
     *  @param _arbitrationPrice Amount to be paid for arbitration.
     */
    constructor(uint256 _arbitrationPrice) {
        arbitrationPrice = _arbitrationPrice;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Set the arbitration price. Only callable by an admin.
     *  @param _arbitrationPrice Amount to be paid for arbitration.
     */
    function setArbitrationPrice(uint256 _arbitrationPrice) external onlyRole(ADMIN_ROLE) {
        uint256 previousPrice = arbitrationPrice;
        arbitrationPrice = _arbitrationPrice;
        emit ArbitrationPriceChanged(previousPrice, _arbitrationPrice);
    }

    /* IArbitrator */
    function createDispute(uint256 _choices, bytes calldata _extraData)
        public
        payable
        override
        returns (uint256 disputeID)
    {
        uint256 requiredAmount = arbitrationCost(_extraData);
        if (msg.value != requiredAmount) {
            revert InsufficientPayment();
        }

        if (_choices > MAX_NUMBER_OF_CHOICES) {
            revert InvalidArguments();
        }

        // Create the dispute and return its number.
        unchecked {
            disputeID = ++lastDispute;
        }

        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 choices = uint8(_choices);
        arbitratorDisputes[disputeID] = ArbitratorDispute({
            arbitrated: IArbitrable(msg.sender), choices: choices, ruling: 0, status: DisputeStatus.Waiting
        });

        emit DisputeCreation(disputeID, IArbitrable(msg.sender));
    }

    /**
     * @dev Cost of arbitration. Accessor to arbitrationPrice.
     *  _extraData Not used by this contract.
     *  @return cost Amount to be paid.
     */
    function arbitrationCost(
        bytes calldata /*_extraData*/
    )
        public
        view
        override
        returns (uint256 cost)
    {
        return arbitrationPrice;
    }

    /**
     * @dev Appeal a ruling. Note that it has to be called before the arbitrator contract calls rule.
     * _disputeID Not used by this contract.
     * _extraData Not used by this contract.
     */
    function appeal(
        uint256,
        /*_disputeID*/
        bytes calldata /*_extraData*/
    )
        external
        payable
        override
    {
        revert InsufficientPayment();
    }

    /**
     * @dev Cost of appeal. If appeal is not possible, it's a high value which can never be paid.
     *  _disputeID Not used by this contract.
     *  _extraData Not used by this contract.
     *  @return cost Amount to be paid.
     */
    function appealCost(
        uint256,
        /*_disputeID*/
        bytes calldata /*_extraData*/
    )
        external
        pure
        override
        returns (uint256 cost)
    {
        return NOT_PAYABLE_VALUE;
    }

    /**
     * @dev Compute the start and end of the dispute's current or next appeal period, if possible. If not known or appeal is impossible: should return (0, 0).
     * _disputeID Not used by this contract.
     * @return start The start of the period.
     * @return end The end of the period.
     */
    function appealPeriod(
        uint256 /*_disputeID*/
    )
        external
        pure
        override
        returns (uint256 start, uint256 end)
    {
        return (0, 0);
    }

    /**
     * @dev Return the status of a dispute.
     * @param _disputeID ID of the dispute to rule.
     * @return status The status of the dispute.
     */
    function disputeStatus(uint256 _disputeID)
        external
        view
        override
        onlyValidDispute(_disputeID)
        returns (DisputeStatus status)
    {
        status = arbitratorDisputes[_disputeID].status;
    }

    /**
     * @dev Return the current ruling of a dispute. This is useful for parties to know if they should appeal.
     * @param _disputeID ID of the dispute.
     * @return ruling The ruling which has been given or the one which will be given if there is no appeal.
     */
    function currentRuling(uint256 _disputeID) external view override onlyValidDispute(_disputeID) returns (uint256) {
        return arbitratorDisputes[_disputeID].ruling;
    }

    /**
     * @dev Give a ruling.
     *  @param _disputeID ID of the dispute to rule.
     *  @param _ruling Ruling given by the arbitrator.
     *                 Note that 0 means "Not able/wanting to make a decision".
     */
    function giveRuling(uint256 _disputeID, uint256 _ruling)
        external
        onlyRole(ADMIN_ROLE)
        onlyValidDispute(_disputeID)
        nonReentrant
    {
        ArbitratorDispute storage dispute = arbitratorDisputes[_disputeID];

        if (_ruling > MAX_NUMBER_OF_CHOICES) {
            revert InvalidRuling(_ruling, MAX_NUMBER_OF_CHOICES);
        }

        if (dispute.status != DisputeStatus.Waiting) {
            revert InvalidStatus(DisputeStatus.Waiting);
        }

        dispute.status = DisputeStatus.Solved;
        // forge-lint: disable-next-line(unsafe-typecast)
        dispute.ruling = uint8(_ruling);

        dispute.arbitrated.rule(_disputeID, _ruling);

        if (!SafeTransfer.sendETH(payable(msg.sender), arbitrationPrice, true)) {
            revert InsufficientPayment();
        }
    }

    function getDispute(uint256 _disputeID)
        external
        view
        onlyValidDispute(_disputeID)
        returns (ArbitratorDispute memory)
    {
        return arbitratorDisputes[_disputeID];
    }
}
