// SPDX-License-Identifier: MIT

/**
 *  @title NerwoCentralizedArbitrator
 *  @author: [@ferittuncer, @hbarcelos, @sherpya]
 *
 *  @notice This contract implement a simple not appealable Centralized Arbitrator
 *  and Arbitrator Proxy, mainly used for test units.
 */

pragma solidity ^0.8.21;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IArbitrator} from "@kleros/erc-792/contracts/IArbitrator.sol";
import {IArbitrable} from "@kleros/erc-792/contracts/IArbitrable.sol";
import {IEvidence} from "@kleros/erc-792/contracts/erc-1497/IEvidence.sol";

import {IArbitrableProxy} from "./IArbitrableProxy.sol";

import {SafeTransfer} from "./SafeTransfer.sol";

contract NerwoCentralizedArbitrator is
    Initializable,
    AccessControl,
    ReentrancyGuard,
    IArbitrable,
    IArbitrator,
    IArbitrableProxy,
    IEvidence
{
    bytes32 public constant COURT_ROLE = keccak256("COURT_ROLE");

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

    IArbitrator public arbitrator = IArbitrator(this);

    uint256 public lastDispute;
    mapping(uint256 => ArbitratorDispute) private arbitratorDisputes;

    uint256 private arbitrationPrice; // Not public because arbitrationCost already acts as an accessor.
    uint256 private constant NOT_PAYABLE_VALUE = type(uint256).max; // High value to be sure that the appeal is too expensive.
    uint256 public constant MAX_NUMBER_OF_CHOICES = 2;

    /**
     * @dev Emitted when the arbitration price is updated by the owner.
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

    /** @dev contructor
     *  @notice set ownership before calling initialize to avoid front running in deployment
     *  @notice since we are using hardhat-deploy deterministic deployment the sender
     *  @notice is 0x4e59b44847b379578588920ca78fbf26c0b4956c
     */
    constructor() {
        /* solhint-disable avoid-tx-origin */
        _setupRole(DEFAULT_ADMIN_ROLE, tx.origin);
    }

    /** @dev initialize (deferred constructor)
     *  @param owner The initial owner
     *  @param court The address list of the court
     *  @param _arbitrationPrice Amount to be paid for arbitration.
     */
    function initialize(
        address owner,
        address[] calldata court,
        uint256 _arbitrationPrice
    ) external onlyRole(DEFAULT_ADMIN_ROLE) initializer {
        if (!hasRole(DEFAULT_ADMIN_ROLE, owner)) {
            _setupRole(DEFAULT_ADMIN_ROLE, owner);
        }

        unchecked {
            for (uint i = 0; i < court.length; i++) {
                _setupRole(COURT_ROLE, court[i]);
            }
        }
        arbitrationPrice = _arbitrationPrice;
    }

    /** @dev Set the arbitration price. Only callable by the owner.
     *  @param _arbitrationPrice Amount to be paid for arbitration.
     */
    function setArbitrationPrice(uint256 _arbitrationPrice) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 previousPrice = arbitrationPrice;
        arbitrationPrice = _arbitrationPrice;
        emit ArbitrationPriceChanged(previousPrice, _arbitrationPrice);
    }

    /* IArbitrator */
    function createDispute(
        uint256 _choices,
        bytes calldata _extraData
    ) public payable override returns (uint256 disputeID) {
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

        arbitratorDisputes[disputeID] = ArbitratorDispute({
            arbitrated: this,
            choices: uint8(_choices),
            ruling: 0,
            status: DisputeStatus.Waiting
        });

        emit DisputeCreation(disputeID, this);
    }

    /** @dev Cost of arbitration. Accessor to arbitrationPrice.
     *  _extraData Not used by this contract.
     *  @return cost Amount to be paid.
     */
    function arbitrationCost(bytes calldata /*_extraData*/) public view override returns (uint256 cost) {
        return arbitrationPrice;
    }

    /**
     * @dev Appeal a ruling. Note that it has to be called before the arbitrator contract calls rule.
     * _disputeID Not used by this contract.
     * _extraData Not used by this contract.
     */
    function appeal(uint256 /*_disputeID*/, bytes calldata /*_extraData*/) external payable override {
        revert InsufficientPayment();
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

    /** @dev To be called by the arbitrator of the dispute, to declare winning ruling.
     *  @param _disputeID ID of the dispute in arbitrator contract.
     *  @param _ruling The ruling choice of the arbitration.
     */
    function rule(uint256 _disputeID, uint256 _ruling) public override onlyValidDispute(_disputeID) {
        if (msg.sender != address(this)) {
            revert InvalidCaller(address(this));
        }

        ArbitratorDispute storage dispute = arbitratorDisputes[_disputeID];

        if (dispute.status == DisputeStatus.Solved) {
            revert AlreadyResolved();
        }

        if (_ruling > MAX_NUMBER_OF_CHOICES) {
            revert InvalidRuling(_ruling, MAX_NUMBER_OF_CHOICES);
        }

        dispute.status = DisputeStatus.Solved;
        dispute.ruling = uint8(_ruling);

        emit Ruling(this, _disputeID, dispute.ruling);
    }

    /** @dev Give a ruling.
     *  @param _disputeID ID of the dispute to rule.
     *  @param _ruling Ruling given by the arbitrator.
     *                 Note that 0 means "Not able/wanting to make a decision".
     */
    function giveRuling(
        uint256 _disputeID,
        uint256 _ruling
    ) external onlyRole(COURT_ROLE) onlyValidDispute(_disputeID) nonReentrant {
        ArbitratorDispute storage dispute = arbitratorDisputes[_disputeID];

        if (_ruling > MAX_NUMBER_OF_CHOICES) {
            revert InvalidRuling(_ruling, MAX_NUMBER_OF_CHOICES);
        }

        if (dispute.status != DisputeStatus.Waiting) {
            revert InvalidStatus(DisputeStatus.Waiting);
        }

        dispute.arbitrated.rule(_disputeID, _ruling);

        SafeTransfer.sendTo(payable(msg.sender), arbitrationPrice, true);
    }

    function getDispute(
        uint256 _disputeID
    ) external view onlyValidDispute(_disputeID) returns (ArbitratorDispute memory) {
        return arbitratorDisputes[_disputeID];
    }

    /* Proxy */
    function createDispute(
        bytes calldata _arbitratorExtraData,
        string calldata _metaevidenceURI,
        uint256 _numberOfRulingOptions
    ) external payable override returns (uint256 disputeID) {
        if (_numberOfRulingOptions > MAX_NUMBER_OF_CHOICES) {
            revert InvalidArguments();
        }

        if (_numberOfRulingOptions == 0) {
            _numberOfRulingOptions = MAX_NUMBER_OF_CHOICES;
        }

        disputeID = createDispute(_numberOfRulingOptions, _arbitratorExtraData);

        emit MetaEvidence(disputeID, _metaevidenceURI);
        emit Dispute(this, disputeID, disputeID, disputeID);
    }

    /** @dev Submit a reference to evidence. EVENT.
     *  @param _localDisputeID The index of the transaction.
     *  @param _evidenceURI Link to evidence.
     */
    function submitEvidence(
        uint256 _localDisputeID,
        string calldata _evidenceURI
    ) external override onlyValidDispute(_localDisputeID) {
        ArbitratorDispute storage dispute = arbitratorDisputes[_localDisputeID];
        if (dispute.status == DisputeStatus.Solved) {
            revert AlreadyResolved();
        }

        emit Evidence(this, _localDisputeID, msg.sender, _evidenceURI);
    }

    function externalIDtoLocalID(uint256 _externalID) external pure override returns (uint256 localID) {
        return _externalID;
    }

    function disputes(
        uint256 _localID
    )
        external
        view
        onlyValidDispute(_localID)
        returns (bytes memory extraData, bool isRuled, uint256 ruling, uint256 disputeIDOnArbitratorSide)
    {
        ArbitratorDispute storage dispute = arbitratorDisputes[_localID];
        return ("", dispute.status == DisputeStatus.Solved, dispute.ruling, _localID);
    }
}
