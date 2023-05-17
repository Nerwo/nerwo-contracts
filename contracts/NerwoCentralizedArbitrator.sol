// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {IArbitrator} from "@kleros/erc-792/contracts/IArbitrator.sol";
import {IArbitrable} from "@kleros/erc-792/contracts/IArbitrable.sol";

error InvalidRuling();
error InvalidCaller(address expected);
error InvalidStatus(uint256 expected);
error AppealPeriodExpired();

error TransferFailed(address recipient, uint256 amount, bytes data);
error InsufficientFunding(uint256 required);

contract NerwoCentralizedArbitrator is Ownable, ReentrancyGuard, IArbitrator, ERC165 {
    using SafeCast for uint256;
    using ERC165Checker for address;

    uint256 private arbitrationPrice; // Not public because arbitrationCost already acts as an accessor.
    uint256 private constant NOT_PAYABLE_VALUE = (2 ** 256 - 2) / 2; // High value to be sure that the appeal is too expensive.

    struct Dispute {
        IArbitrable arbitrated; // The contract requiring arbitration.
        DisputeStatus status; // The status of the dispute.
        uint8 choices; // The amount of possible choices, 0 excluded.
        uint8 ruling; // The current ruling.
        uint32 appealPeriodStart; // The start of the appeal period. 0 before it is appealable.
        uint32 appealPeriodEnd; // The end of the appeal Period. 0 before it is appealable.
        uint256 fees; // The total amount of fees collected by the arbitrator.
        uint256 appealCost; // The cost to appeal. 0 before it is appealable.
    }

    Dispute[] private disputes;

    modifier requireArbitrationFee(bytes calldata _extraData) {
        uint256 required = arbitrationCost(_extraData);
        if (msg.value != required) {
            revert InsufficientFunding(required);
        }
        _;
    }

    modifier requireAppealFee(uint256 _disputeID, bytes calldata _extraData) {
        uint256 required = appealCost(_disputeID, _extraData);
        if (msg.value != required) {
            revert InsufficientFunding(required);
        }
        _;
    }

    /**
     * @dev Emitted when the arbitration price is updated by the owner.
     * @param previousPrice The previous arbitration price.
     * @param newPrice The updated arbitration price.
     */
    event ArbitrationPriceChanged(uint256 previousPrice, uint256 newPrice);

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

    /** @dev Cost of arbitration. Accessor to arbitrationPrice.
     *  _extraData Not used by this contract.
     *  @return fee Amount to be paid.
     */
    function arbitrationCost(bytes calldata) public view returns (uint256 fee) {
        return arbitrationPrice;
    }

    /** @dev Cost of appeal. If appeal is not possible, it's a high value which can never be paid.
     *  @param _disputeID ID of the dispute to be appealed.
     *  _extraData Not used by this contract.
     *  @return fee Amount to be paid.
     */
    function appealCost(uint256 _disputeID, bytes calldata) public view returns (uint256 fee) {
        Dispute storage dispute = disputes[_disputeID];
        if (dispute.status == DisputeStatus.Appealable) {
            return dispute.appealCost;
        }

        return NOT_PAYABLE_VALUE;
    }

    /** @dev Create a dispute. Must be called by the arbitrable contract.
     *  Must be paid at least arbitrationCost().
     *  @param _choices Amount of choices the arbitrator can make in this dispute. When ruling <= choices.
     *  @param _extraData Can be used to give additional info on the dispute to be created.
     *  @return disputeID ID of the dispute created.
     */
    function createDispute(
        uint256 _choices,
        bytes calldata _extraData
    ) external payable requireArbitrationFee(_extraData) returns (uint256 disputeID) {
        // Create the dispute and return its number.
        IArbitrable arbitrable = IArbitrable(_msgSender());

        if (!_msgSender().supportsInterface(type(IArbitrable).interfaceId)) {
            revert InvalidCaller(address(0));
        }

        disputeID = disputes.length;

        disputes.push(
            Dispute({
                arbitrated: arbitrable,
                choices: _choices.toUint8(),
                fees: msg.value,
                ruling: 0,
                status: DisputeStatus.Waiting,
                appealCost: 0,
                appealPeriodStart: 0,
                appealPeriodEnd: 0
            })
        );
        emit DisputeCreation(disputeID, arbitrable);
    }

    /** @dev Give a ruling. UNTRUSTED.
     *  @param _disputeID ID of the dispute to rule.
     *  @param _ruling Ruling given by the arbitrator. Note that 0 means "Not able/wanting to make a decision".
     */
    function giveRuling(uint256 _disputeID, uint256 _ruling) external onlyOwner {
        Dispute storage dispute = disputes[_disputeID];

        if (dispute.status != DisputeStatus.Waiting) {
            revert InvalidStatus(uint256(DisputeStatus.Waiting));
        }

        if (_ruling > dispute.choices) {
            revert InvalidRuling();
        }

        dispute.ruling = _ruling.toUint8();
        dispute.status = DisputeStatus.Solved;

        // FIXME: emit only log instead of failing?
        _transferTo(payable(_msgSender()), dispute.fees);

        dispute.arbitrated.rule(_disputeID, _ruling);
    }

    /** @dev Give an appealable ruling.
     *  @param _disputeID ID of the dispute to rule.
     *  @param _ruling Ruling given by the arbitrator. Note that 0 means "Not able/wanting to make a decision".
     *  @param _appealCost The cost of appeal.
     *  @param _timeToAppeal The time to appeal the ruling.
     */
    function giveAppealableRuling(
        uint256 _disputeID,
        uint256 _ruling,
        uint256 _appealCost,
        uint256 _timeToAppeal
    ) external onlyOwner {
        Dispute storage dispute = disputes[_disputeID];

        if (_ruling > dispute.choices) {
            revert InvalidRuling();
        }

        if (dispute.status != DisputeStatus.Waiting) {
            revert InvalidStatus(uint256(DisputeStatus.Waiting));
        }

        uint32 _now = uint32(block.timestamp);

        dispute.ruling = _ruling.toUint8();
        dispute.status = DisputeStatus.Appealable;
        dispute.appealCost = _appealCost;
        dispute.appealPeriodStart = _now;
        dispute.appealPeriodEnd = (_now + _timeToAppeal).toUint32(); //  just let it fail on overflow

        emit AppealPossible(_disputeID, dispute.arbitrated);
    }

    /** @dev Change the appeal fee of a dispute.
     *  @param _disputeID The ID of the dispute to update.
     *  @param _appealCost The new cost to appeal this ruling.
     */
    function changeAppealFee(uint256 _disputeID, uint256 _appealCost) external onlyOwner {
        Dispute storage dispute = disputes[_disputeID];

        if (dispute.status != DisputeStatus.Appealable) {
            revert InvalidStatus(uint256(DisputeStatus.Appealable));
        }

        dispute.appealCost = _appealCost;
    }

    /** @dev Appeal a ruling. Note that it has to be called before the arbitrator contract calls rule.
     *  @param _disputeID ID of the dispute to be appealed.
     *  @param _extraData Can be used to give extra info on the appeal.
     */
    function appeal(
        uint256 _disputeID,
        bytes calldata _extraData
    ) external payable requireAppealFee(_disputeID, _extraData) {
        Dispute storage dispute = disputes[_disputeID];

        if (dispute.status != DisputeStatus.Appealable) {
            revert InvalidStatus(uint256(DisputeStatus.Appealable));
        }

        if (block.timestamp >= dispute.appealPeriodEnd) {
            revert AppealPeriodExpired();
        }

        dispute.fees += msg.value;
        dispute.status = DisputeStatus.Waiting;
        emit AppealDecision(_disputeID, IArbitrable(_msgSender()));
    }

    /** @dev Return the status of a dispute (in the sense of ERC792, not the Dispute property).
     *  @param _disputeID ID of the dispute to rule.
     *  @return status The status of the dispute.
     */
    function disputeStatus(uint256 _disputeID) external view returns (DisputeStatus status) {
        Dispute storage dispute = disputes[_disputeID];
        if (disputes[_disputeID].status == DisputeStatus.Appealable && block.timestamp >= dispute.appealPeriodEnd) {
            // If the appeal period is over, consider it solved even if rule has not been called yet.
            return DisputeStatus.Solved;
        }
        return disputes[_disputeID].status;
    }

    /** @dev Return the ruling of a dispute.
     *  @param _disputeID ID of the dispute.
     *  @return ruling The ruling which have been given or which would be given if no appeals are raised.
     */
    function currentRuling(uint256 _disputeID) external view returns (uint256 ruling) {
        return disputes[_disputeID].ruling;
    }

    /** @dev Compute the start and end of the dispute's current or next appeal period, if possible.
     *  @param _disputeID ID of the dispute.
     *  @return start end The start and end of the period.
     */
    function appealPeriod(uint256 _disputeID) external view returns (uint256 start, uint256 end) {
        Dispute storage dispute = disputes[_disputeID];
        return (dispute.appealPeriodStart, dispute.appealPeriodEnd);
    }
}
