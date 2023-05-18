// SPDX-License-Identifier: MIT

/**
 *  @title NerwoCentralizedArbitrator
 *  @author: [@ferittuncer, @hbarcelos, @sherpya]
 *
 *  @notice This contract implement a simple not appealable Centralized Arbitrator
 */

pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IArbitrator} from "@kleros/erc-792/contracts/IArbitrator.sol";
import {IArbitrable} from "@kleros/erc-792/contracts/IArbitrable.sol";

contract NerwoCentralizedArbitrator is Ownable, ReentrancyGuard, IArbitrator, ERC165 {
    using ERC165Checker for address;
    using SafeCast for uint256;

    error InsufficientPayment(uint256 _available, uint256 _required);
    error InvalidRuling(uint256 _ruling, uint256 _numberOfChoices);
    error InvalidStatus(DisputeStatus _current, DisputeStatus _expected);

    error TransferFailed(address recipient, uint256 amount, bytes data);
    error InvalidCaller(address expected);
    error InvalidDispute(uint256 disputeID);

    struct Dispute {
        IArbitrable arbitrated;
        uint8 choices;
        uint8 ruling;
        DisputeStatus status;
    }

    uint256 public index;
    mapping(uint256 => Dispute) public disputes;
    uint256 private arbitrationPrice; // Not public because arbitrationCost already acts as an accessor.
    uint256 private constant NOT_PAYABLE_VALUE = type(uint256).max; // High value to be sure that the appeal is too expensive.

    /**
     * @dev Emitted when the arbitration price is updated by the owner.
     * @param previousPrice The previous arbitration price.
     * @param newPrice The updated arbitration price.
     */
    event ArbitrationPriceChanged(uint256 previousPrice, uint256 newPrice);

    modifier onlyValidDispute(uint256 _disputeID) {
        if (address(disputes[_disputeID].arbitrated) == address(0)) {
            revert InvalidDispute(_disputeID);
        }
        _;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IArbitrator).interfaceId || super.supportsInterface(interfaceId);
    }

    /** @dev initializer
     *  @param _owner The initial owner
     *  @param _arbitrationPrice Amount to be paid for arbitration.
     */
    constructor(address _owner, uint256 _arbitrationPrice) {
        arbitrationPrice = _arbitrationPrice;
        _transferOwnership(_owner);
    }

    /** @dev Send to recipent, reverts on failure
     *  @param target To address to send to
     *  @param amount Transaction amount
     */
    function _transferTo(address payable target, uint256 amount) internal {
        (bool success, bytes memory data) = target.call{value: amount}("");
        if (!success) {
            revert TransferFailed(target, amount, data);
        }
    }

    /** @dev Set the arbitration price. Only callable by the owner.
     *  @param _arbitrationPrice Amount to be paid for arbitration.
     */
    function setArbitrationPrice(uint256 _arbitrationPrice) external onlyOwner {
        uint256 previousPrice = arbitrationPrice;
        arbitrationPrice = _arbitrationPrice;
        emit ArbitrationPriceChanged(previousPrice, _arbitrationPrice);
    }

    function createDispute(
        uint256 _choices,
        bytes calldata _extraData
    ) external payable override returns (uint256 disputeID) {
        uint256 requiredAmount = arbitrationCost(_extraData);
        if (msg.value != requiredAmount) {
            revert InsufficientPayment(msg.value, requiredAmount);
        }

        if (!_msgSender().supportsInterface(type(IArbitrable).interfaceId)) {
            revert InvalidCaller(address(0));
        }

        IArbitrable arbitrabled = IArbitrable(_msgSender());

        // Create the dispute and return its number.
        disputeID = ++index;
        disputes[disputeID] = Dispute({
            arbitrated: arbitrabled,
            choices: _choices.toUint8(),
            ruling: 0,
            status: DisputeStatus.Waiting
        });

        emit DisputeCreation(disputeID, arbitrabled);
    }

    /** @dev Cost of arbitration. Accessor to arbitrationPrice.
     *  _extraData Not used by this contract.
     *  @return cost Amount to be paid.
     */
    function arbitrationCost(bytes memory /*_extraData*/) public view override returns (uint256 cost) {
        return arbitrationPrice;
    }

    /**
     * @dev Appeal a ruling. Note that it has to be called before the arbitrator contract calls rule.
     * _disputeID Not used by this contract.
     * _extraData Not used by this contract.
     */
    function appeal(uint256 /*_disputeID*/, bytes calldata /*_extraData*/) external payable override {
        revert InsufficientPayment(msg.value, NOT_PAYABLE_VALUE);
    }

    /** @dev Cost of appeal. If appeal is not possible, it's a high value which can never be paid.
     *  _disputeID Not used by this contract.
     *  _extraData Not used by this contract.
     *  @return cost Amount to be paid.
     */
    function appealCost(
        uint256 /*_disputeID*/,
        bytes calldata /*_extraData*/
    ) external pure override returns (uint256 cost) {
        return NOT_PAYABLE_VALUE;
    }

    /**
     * @dev Compute the start and end of the dispute's current or next appeal period, if possible. If not known or appeal is impossible: should return (0, 0).
     * _disputeID Not used by this contract.
     * @return start The start of the period.
     * @return end The end of the period.
     */
    function appealPeriod(uint256 /*_disputeID*/) external pure override returns (uint256 start, uint256 end) {
        return (0, 0);
    }

    /**
     * @dev Return the status of a dispute.
     * @param _disputeID ID of the dispute to rule.
     * @return status The status of the dispute.
     */
    function disputeStatus(
        uint256 _disputeID
    ) external view override onlyValidDispute(_disputeID) returns (DisputeStatus status) {
        status = disputes[_disputeID].status;
    }

    /**
     * @dev Return the current ruling of a dispute. This is useful for parties to know if they should appeal.
     * @param _disputeID ID of the dispute.
     * @return ruling The ruling which has been given or the one which will be given if there is no appeal.
     */
    function currentRuling(
        uint256 _disputeID
    ) external view override onlyValidDispute(_disputeID) returns (uint256 ruling) {
        ruling = disputes[_disputeID].ruling;
    }

    /** @dev Give a ruling.
     *  @param _disputeID ID of the dispute to rule.
     *  @param _ruling Ruling given by the arbitrator.
     *                 Note that 0 means "Not able/wanting to make a decision".
     */
    function giveRuling(
        uint256 _disputeID,
        uint256 _ruling
    ) external onlyValidDispute(_disputeID) onlyOwner nonReentrant {
        Dispute storage dispute = disputes[_disputeID];

        if (_ruling > dispute.choices) {
            revert InvalidRuling(_ruling, dispute.choices);
        }

        if (dispute.status != DisputeStatus.Waiting) {
            revert InvalidStatus(dispute.status, DisputeStatus.Waiting);
        }

        dispute.ruling = _ruling.toUint8();
        dispute.status = DisputeStatus.Solved;

        _transferTo(payable(_msgSender()), arbitrationCost(""));

        dispute.arbitrated.rule(_disputeID, _ruling);
    }
}
