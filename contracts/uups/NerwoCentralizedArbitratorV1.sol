// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {VersionAware} from "../VersionAware.sol";
import {IArbitrator} from "../kleros/IArbitrator.sol";
import {IArbitrable} from "../kleros/IArbitrable.sol";

contract NerwoCentralizedArbitratorV1 is IArbitrator, UUPSUpgradeable, OwnableUpgradeable, VersionAware {
    string private constant CONTRACT_NAME = "NerwoCentralizedArbitrator: V1";

    enum DisputeStatus {
        Waiting,
        Appealable,
        Solved
    }

    uint256 private arbitrationPrice; // Not public because arbitrationCost already acts as an accessor.
    uint256 private constant NOT_PAYABLE_VALUE = (2 ** 256 - 2) / 2; // High value to be sure that the appeal is too expensive.

    struct Dispute {
        IArbitrable arbitrated; // The contract requiring arbitration.
        DisputeStatus status; // The status of the dispute.
        uint8 choices; // The amount of possible choices, 0 excluded.
        uint8 ruling; // The current ruling.
        uint64 appealPeriodStart; // The start of the appeal period. 0 before it is appealable.
        uint64 appealPeriodEnd; // The end of the appeal Period. 0 before it is appealable.
        uint256 fees; // The total amount of fees collected by the arbitrator.
        uint256 appealCost; // The cost to appeal. 0 before it is appealable.
    }

    Dispute[] public disputes;

    modifier requireArbitrationFee(bytes calldata _extraData) {
        require(msg.value >= arbitrationCost(_extraData), "Not enough ETH to cover arbitration costs.");
        _;
    }

    modifier requireAppealFee(uint256 _disputeID, bytes calldata _extraData) {
        require(msg.value >= appealCost(_disputeID, _extraData), "Not enough ETH to cover appeal costs.");
        _;
    }

    /** @dev To be raised when a dispute can be appealed.
     *  @param _disputeID ID of the dispute.
     *  @param _arbitrable The contract which created the dispute.
     */
    event AppealPossible(uint256 indexed _disputeID, IArbitrable indexed _arbitrable);

    /** @dev To be raised when the current ruling is appealed.
     *  @param _disputeID ID of the dispute.
     *  @param _arbitrable The contract which created the dispute.
     */
    event AppealDecision(uint256 indexed _disputeID, IArbitrable indexed _arbitrable);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /** @dev initializer
     *  @param _arbitrationPrice Amount to be paid for arbitration.
     */
    function initialize(uint256 _arbitrationPrice) external initializer {
        arbitrationPrice = _arbitrationPrice;
        versionAwareContractName = CONTRACT_NAME;
        ///@dev as there is no constructor, we need to initialise the OwnableUpgradeable explicitly
        __Ownable_init();
    }

    // Here only to test upgrade
    /*
    function initialize2(uint256 _arbitrationPrice) external reinitializer(2) {
        arbitrationPrice = _arbitrationPrice;
        versionAwareContractName = "NerwoCentralizedArbitrator: V2";
        ///@dev as there is no constructor, we need to initialise the OwnableUpgradeable explicitly
        __Ownable_init();
    }*/

    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function getContractNameWithVersion() external pure override returns (string memory) {
        return CONTRACT_NAME;
    }

    /** @dev Set the arbitration price. Only callable by the owner.
     *  @param _arbitrationPrice Amount to be paid for arbitration.
     */
    function setArbitrationPrice(uint256 _arbitrationPrice) external onlyOwner {
        arbitrationPrice = _arbitrationPrice;
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
        Dispute memory dispute = disputes[_disputeID];
        if (dispute.status == DisputeStatus.Appealable) return dispute.appealCost;
        else return NOT_PAYABLE_VALUE;
    }

    /** @dev Create a dispute. Must be called by the arbitrable contract.
     *  Must be paid at least arbitrationCost().
     *  @param _choices Amount of choices the arbitrator can make in this dispute. When ruling <= choices.
     *  _extraData Can be used to give additional info on the dispute to be created.
     *  @return disputeID ID of the dispute created.
     */
    function createDispute(uint256 _choices, bytes calldata) external payable returns (uint256 disputeID) {
        // Create the dispute and return its number.
        disputes.push(
            Dispute({
                arbitrated: IArbitrable(_msgSender()),
                choices: uint8(_choices),
                fees: msg.value,
                ruling: 0,
                status: DisputeStatus.Waiting,
                appealCost: 0,
                appealPeriodStart: 0,
                appealPeriodEnd: 0
            })
        );
        disputeID = disputes.length - 1;
        emit DisputeCreation(disputeID, IArbitrable(_msgSender()));
    }

    /** @dev Give a ruling. UNTRUSTED.
     *  @param _disputeID ID of the dispute to rule.
     *  @param _ruling Ruling given by the arbitrator. Note that 0 means "Not able/wanting to make a decision".
     */
    function giveRuling(uint256 _disputeID, uint256 _ruling) external onlyOwner {
        Dispute storage dispute = disputes[_disputeID];
        require(_ruling <= dispute.choices, "Invalid ruling.");
        require(dispute.status == DisputeStatus.Waiting, "The dispute must be waiting for arbitration.");

        dispute.ruling = uint8(_ruling);
        dispute.status = DisputeStatus.Solved;

        (bool success, ) = payable(_msgSender()).call{value: dispute.fees}("");
        require(success, "Failed to send dispute fee.");

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
        require(_ruling <= dispute.choices, "Invalid ruling.");
        require(dispute.status == DisputeStatus.Waiting, "The dispute must be waiting for arbitration.");

        uint64 _now = uint64(block.timestamp);

        dispute.ruling = uint8(_ruling);
        dispute.status = DisputeStatus.Appealable;
        dispute.appealCost = _appealCost;
        dispute.appealPeriodStart = _now;
        dispute.appealPeriodEnd = uint64(_now + _timeToAppeal); //  just let it fail on overflow

        emit AppealPossible(_disputeID, dispute.arbitrated);
    }

    /** @dev Change the appeal fee of a dispute.
     *  @param _disputeID The ID of the dispute to update.
     *  @param _appealCost The new cost to appeal this ruling.
     */
    function changeAppealFee(uint256 _disputeID, uint256 _appealCost) external onlyOwner {
        Dispute storage dispute = disputes[_disputeID];
        require(dispute.status == DisputeStatus.Appealable, "The dispute must be appealable.");

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
        require(dispute.status == DisputeStatus.Appealable, "The dispute must be appealable.");
        require(
            block.timestamp < dispute.appealPeriodEnd,
            "The appeal must occur before the end of the appeal period."
        );

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
        if (disputes[_disputeID].status == DisputeStatus.Appealable && block.timestamp >= dispute.appealPeriodEnd)
            // If the appeal period is over, consider it solved even if rule has not been called yet.
            return DisputeStatus.Solved;
        else return disputes[_disputeID].status;
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
