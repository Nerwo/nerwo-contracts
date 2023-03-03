// SPDX-License-Identifier: MIT
/**
 *  @authors: [@eburgos, @n1c01a5, @sherpya]
 *  @reviewers: [@unknownunknown1, @clesaege*, @ferittuncer, @remedcu]
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 *  @tools: [MythX]
 */

pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {VersionAware} from "../VersionAware.sol";

import {IArbitrator} from "../kleros/IArbitrator.sol";
import {IArbitrable} from "../kleros/IArbitrable.sol";

contract NerwoEscrowV1 is IArbitrable, Initializable, UUPSUpgradeable, OwnableUpgradeable, VersionAware {
    // **************************** //
    // *    Contract variables    * //
    // **************************** //
    string private constant CONTRACT_NAME = "NerwoEscrow: V1";

    uint8 private constant AMOUNT_OF_CHOICES = 2;
    uint8 private constant SENDER_WINS = 1;
    uint8 private constant RECEIVER_WINS = 2;

    // ReentrancyGuard
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    enum Party {
        Sender,
        Receiver
    }

    enum Status {
        NoDispute,
        WaitingSender,
        WaitingReceiver,
        DisputeCreated,
        Resolved
    }

    struct Transaction {
        Status status;
        address payable sender;
        address payable receiver;
        uint64 timeoutPayment; // Time in seconds after which the transaction can be automatically executed if not disputed.
        uint64 lastInteraction; // Last interaction for the dispute procedure.
        uint256 amount;
        uint256 disputeId; // If dispute exists, the ID of the dispute.
        uint256 senderFee; // Total fees paid by the sender.
        uint256 receiverFee; // Total fees paid by the receiver.
    }

    // ReentrancyGuard
    uint256 private _status;

    Transaction[] private transactions;
    bytes public arbitratorExtraData; // Extra data to set up the arbitration.
    IArbitrator public arbitrator; // Address of the arbitrator contract.

    uint256 public feeTimeout; // Time in seconds a party can take to pay arbitration fees before being considered unresponding and lose the dispute.

    address payable public feeRecipient; // Address which receives a share of receiver payment.
    uint256 public feeRecipientBasisPoint; // The share of fee to be received by the feeRecipient, down to 2 decimal places as 550 = 5.5%.

    mapping(uint256 => uint256) private disputeIDtoTransactionID; // One-to-one relationship between the dispute and the transaction.

    // **************************** //
    // *          Events          * //
    // **************************** //

    /** @dev To be emitted when a party pays or reimburses the other.
     *  @param _transactionID The index of the transaction.
     *  @param _amount The amount paid.
     *  @param _party The party that paid.
     */
    event Payment(uint256 indexed _transactionID, uint256 _amount, address _party);

    /** @dev Indicate that a party has to pay a fee or would otherwise be considered as losing.
     *  @param _transactionID The index of the transaction.
     *  @param _party The party who has to pay.
     */
    event HasToPayFee(uint256 indexed _transactionID, Party _party);

    /** @dev Emitted when a transaction is created.
     *  @param _transactionID The index of the transaction.
     *  @param _sender The address of the sender.
     *  @param _receiver The address of the receiver.
     *  @param _amount The initial amount in the transaction.
     */
    event TransactionCreated(
        uint256 _transactionID,
        address indexed _sender,
        address indexed _receiver,
        uint256 _amount
    );

    /** @dev To be emitted when a fee is received by the feeRecipient.
     *  @param _transactionID The index of the transaction.
     *  @param _amount The amount paid.
     */
    event FeeRecipientPayment(uint256 indexed _transactionID, uint256 _amount);

    /** @dev To be emitted when a feeRecipient is changed.
     *  @param _oldFeeRecipient Previous feeRecipient.
     *  @param _newFeeRecipient Current feeRecipient.
     */
    event FeeRecipientChanged(address indexed _oldFeeRecipient, address indexed _newFeeRecipient);

    /** @dev To be emmited when meta-evidence is submitted.
     *  @param _metaEvidenceID Unique identifier of meta-evidence.
     *  @param _evidence A link to the meta-evidence JSON.
     */
    event MetaEvidence(uint256 indexed _metaEvidenceID, string _evidence);

    /** @dev To be emmited when a dispute is created to link the correct meta-evidence to the disputeID
     *  @param _arbitrator The arbitrator of the contract.
     *  @param _disputeID ID of the dispute in the Arbitrator contract.
     *  @param _metaEvidenceID Unique identifier of meta-evidence.
     *  @param _evidenceGroupID Unique identifier of the evidence group that is linked to this dispute.
     */
    event Dispute(
        IArbitrator indexed _arbitrator,
        uint256 indexed _disputeID,
        uint256 _metaEvidenceID,
        uint256 _evidenceGroupID
    );

    /** @dev To be raised when evidence are submitted. Should point to the resource (evidences are not to be stored on chain due to gas considerations).
     *  @param _arbitrator The arbitrator of the contract.
     *  @param _evidenceGroupID Unique identifier of the evidence group the evidence belongs to.
     *  @param _party The address of the party submiting the evidence. Note that 0x0 refers to evidence not submitted by any party.
     *  @param _evidence A URI to the evidence JSON file whose name should be its keccak256 hash followed by .json.
     */
    event Evidence(
        IArbitrator indexed _arbitrator,
        uint256 indexed _evidenceGroupID,
        address indexed _party,
        string _evidence
    );

    /** @dev To be emitted if a transfer to a party fails
     *  @param recipient The target of the failed operation
     *  @param amount The amount
     *  @param data Failed call data
     */
    event SendFailed(address recipient, uint256 amount, bytes data);

    // **************************** //
    // *    Arbitrable functions  * //
    // *    Modifying the state   * //
    // **************************** //

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /** @dev initializer
     *  @param _arbitrator The arbitrator of the contract.
     *  @param _arbitratorExtraData Extra data for the arbitrator.
     *  @param _feeRecipient Address which receives a share of receiver payment.
     *  @param _feeRecipientBasisPoint The share of fee to be received by the feeRecipient, down to 2 decimal places as 550 = 5.5%.
     *  @param _feeTimeout Arbitration fee timeout for the parties.
     */
    function initialize(
        address _arbitrator,
        bytes calldata _arbitratorExtraData,
        address _feeRecipient,
        uint256 _feeRecipientBasisPoint,
        uint256 _feeTimeout
    ) external initializer {
        _status = _NOT_ENTERED;
        versionAwareContractName = CONTRACT_NAME;
        _setArbitrator(_arbitrator, _arbitratorExtraData, _feeRecipient, _feeRecipientBasisPoint, _feeTimeout);
        ///@dev as there is no constructor, we need to initialise the OwnableUpgradeable explicitly
        __Ownable_init();
    }

    // Here only to test upgrade
    /*
    function initialize2(
        address _arbitrator,
        bytes calldata _arbitratorExtraData,
        address _feeRecipient,
        uint256 _feeRecipientBasisPoint,
        uint256 _feeTimeout
    ) external reinitializer(2) {
        _status = _NOT_ENTERED;
        _setArbitrator(_arbitrator, _arbitratorExtraData, _feeRecipient, _feeRecipientBasisPoint, _feeTimeout);
        versionAwareContractName = "NerwoEscrow: V2";
        ///@dev as there is no constructor, we need to initialise the OwnableUpgradeable explicitly
        __Ownable_init();
    }*/

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function setArbitrator(
        address _arbitrator,
        bytes calldata _arbitratorExtraData,
        address _feeRecipient,
        uint256 _feeRecipientBasisPoint,
        uint256 _feeTimeout
    ) external onlyOwner {
        _setArbitrator(_arbitrator, _arbitratorExtraData, _feeRecipient, _feeRecipientBasisPoint, _feeTimeout);
    }

    /**
     * @dev modifies Arbitrator and paramameters
     * Internal function without access restriction.
     */
    function _setArbitrator(
        address _arbitrator,
        bytes calldata _arbitratorExtraData,
        address _feeRecipient,
        uint256 _feeRecipientBasisPoint,
        uint256 _feeTimeout
    ) internal {
        arbitrator = IArbitrator(_arbitrator);
        arbitratorExtraData = _arbitratorExtraData;
        feeTimeout = _feeTimeout;
        feeRecipient = payable(_feeRecipient);
        feeRecipientBasisPoint = _feeRecipientBasisPoint;
    }

    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function getContractNameWithVersion() external pure override returns (string memory) {
        return CONTRACT_NAME;
    }

    /** @dev Calculate the amount to be paid in wei according to feeRecipientBasisPoint for a particular amount.
     *  @param _amount Amount to pay in wei.
     */
    function calculateFeeRecipientAmount(uint256 _amount) internal view returns (uint256) {
        return (_amount * feeRecipientBasisPoint) / 10000;
    }

    /** @dev Change Fee Recipient.
     *  @param _newFeeRecipient Address of the new Fee Recipient.
     */
    function changeFeeRecipient(address _newFeeRecipient) external {
        require(_msgSender() == feeRecipient, "The caller must be the current Fee Recipient");
        feeRecipient = payable(_newFeeRecipient);

        emit FeeRecipientChanged(_msgSender(), _newFeeRecipient);
    }

    /** @dev Create a transaction.
     *  @param _timeoutPayment Time after which a party can automatically execute the arbitrable transaction.
     *  @param _receiver The recipient of the transaction.
     *  @param _metaEvidence Link to the meta-evidence.
     *  @return transactionID The index of the transaction.
     */
    function createTransaction(
        uint256 _timeoutPayment,
        address _receiver,
        string calldata _metaEvidence
    ) external payable returns (uint256 transactionID) {
        transactions.push(
            Transaction({
                sender: payable(_msgSender()),
                receiver: payable(_receiver),
                amount: msg.value,
                timeoutPayment: uint64(_timeoutPayment),
                disputeId: 0,
                senderFee: 0,
                receiverFee: 0,
                lastInteraction: uint64(block.timestamp),
                status: Status.NoDispute
            })
        );

        transactionID = transactions.length - 1;

        emit MetaEvidence(transactionID, _metaEvidence);
        emit TransactionCreated(transactionID, _msgSender(), _receiver, msg.value);
    }

    /** @dev Send to recipent, emit a log when fails
     *  @param target To address to send to
     *  @param amount Transaction amount
     */
    function _sendTo(address payable target, uint256 amount) internal {
        (bool success, bytes memory data) = target.call{value: amount}("");
        if (!success) {
            emit SendFailed(target, amount, data);
        }
    }

    /** @dev Send to recipent, reverts on failure
     *  @param target To address to send to
     *  @param amount Transaction amount
     */
    function _transferTo(address payable target, uint256 amount) internal {
        (bool success, ) = target.call{value: amount}("");
        require(success, "Transfer failed");
    }

    /** @dev Pay receiver. To be called if the good or service is provided.
     *  @param _transactionID The index of the transaction.
     *  @param _amount Amount to pay in wei.
     */
    function pay(uint256 _transactionID, uint256 _amount) external nonReentrant {
        Transaction storage transaction = transactions[_transactionID];
        require(transaction.sender == _msgSender(), "The caller must be the sender.");
        require(transaction.status == Status.NoDispute, "The transaction shouldn't be disputed.");
        require(_amount <= transaction.amount, "The amount paid has to be less than or equal to the transaction.");

        transaction.amount -= _amount; // reentrancy safe

        uint256 feeAmount = calculateFeeRecipientAmount(_amount);
        _transferTo(feeRecipient, feeAmount);

        _sendTo(transaction.receiver, _amount - feeAmount);

        emit Payment(_transactionID, _amount, _msgSender());
        emit FeeRecipientPayment(_transactionID, feeAmount);
    }

    /** @dev Reimburse sender. To be called if the good or service can't be fully provided.
     *  @param _transactionID The index of the transaction.
     *  @param _amountReimbursed Amount to reimburse in wei.
     */
    function reimburse(uint256 _transactionID, uint256 _amountReimbursed) external nonReentrant {
        Transaction storage transaction = transactions[_transactionID];
        require(transaction.receiver == _msgSender(), "The caller must be the receiver.");
        require(transaction.status == Status.NoDispute, "The transaction shouldn't be disputed.");
        require(
            _amountReimbursed <= transaction.amount,
            "The amount reimbursed has to be less or equal than the transaction."
        );

        transaction.amount -= _amountReimbursed; // reentrancy safe
        _sendTo(transaction.sender, _amountReimbursed);

        emit Payment(_transactionID, _amountReimbursed, _msgSender());
    }

    /** @dev Transfer the transaction's amount to the receiver if the timeout has passed.
     *  @param _transactionID The index of the transaction.
     */
    function executeTransaction(uint256 _transactionID) external nonReentrant {
        Transaction storage transaction = transactions[_transactionID];
        require(transaction.status == Status.NoDispute, "The transaction shouldn't be disputed.");
        require(
            block.timestamp - transaction.lastInteraction >= transaction.timeoutPayment,
            "The timeout has not passed yet."
        );

        transaction.status = Status.Resolved; // reentrancy safe

        uint256 amount = transaction.amount;
        transaction.amount = 0; // reentrancy safe

        uint256 feeAmount = calculateFeeRecipientAmount(amount);
        _transferTo(feeRecipient, feeAmount);

        _sendTo(transaction.receiver, amount - feeAmount);

        emit FeeRecipientPayment(_transactionID, feeAmount);
    }

    /** @dev Reimburse sender if receiver fails to pay the fee.
     *  @param _transactionID The index of the transaction.
     */
    function timeOutBySender(uint256 _transactionID) external nonReentrant {
        Transaction storage transaction = transactions[_transactionID];
        require(transaction.status == Status.WaitingReceiver, "The transaction is not waiting on the receiver.");
        require(block.timestamp - transaction.lastInteraction >= feeTimeout, "Timeout time has not passed yet.");

        if (transaction.receiverFee != 0) {
            uint256 receiverFee = transaction.receiverFee;
            transaction.receiverFee = 0; // reentrancy safe
            _sendTo(transaction.receiver, receiverFee);
        }

        // reentrancy safe -> Status.Resolved
        _executeRuling(_transactionID, SENDER_WINS);
    }

    /** @dev Pay receiver if sender fails to pay the fee.
     *  @param _transactionID The index of the transaction.
     */
    function timeOutByReceiver(uint256 _transactionID) external nonReentrant {
        Transaction storage transaction = transactions[_transactionID];
        require(transaction.status == Status.WaitingSender, "The transaction is not waiting on the sender.");
        require(block.timestamp - transaction.lastInteraction >= feeTimeout, "Timeout time has not passed yet.");

        if (transaction.senderFee != 0) {
            uint256 senderFee = transaction.senderFee;
            transaction.senderFee = 0; // reentrancy safe
            _sendTo(transaction.sender, senderFee);
        }

        // reentrancy safe -> Status.Resolved
        _executeRuling(_transactionID, RECEIVER_WINS);
    }

    /** @dev Pay the arbitration fee to raise a dispute. To be called by the sender. UNTRUSTED.
     *  Note that the arbitrator can have createDispute throw, which will make this function throw and therefore lead to a party being timed-out.
     *  This is not a vulnerability as the arbitrator can rule in favor of one party anyway.
     *  @param _transactionID The index of the transaction.
     */
    function payArbitrationFeeBySender(uint256 _transactionID) external payable nonReentrant {
        Transaction storage transaction = transactions[_transactionID];
        require(
            transaction.status < Status.DisputeCreated,
            "Dispute has already been created or because the transaction has been executed."
        );
        require(_msgSender() == transaction.sender, "The caller must be the sender.");

        uint256 arbitrationCost = arbitrator.arbitrationCost(arbitratorExtraData);
        transaction.senderFee = msg.value;

        // Require that the total pay at least the arbitration cost.
        require(transaction.senderFee == arbitrationCost, "The sender fee must cover arbitration costs.");

        transaction.lastInteraction = uint64(block.timestamp);

        // The receiver still has to pay. This can also happen if he has paid, but arbitrationCost has increased.
        if (transaction.receiverFee == 0) {
            transaction.status = Status.WaitingReceiver;
            emit HasToPayFee(_transactionID, Party.Receiver);
        } else {
            // The receiver has also paid the fee. We create the dispute.
            // reentrancy safe -> Status.DisputeCreated
            _raiseDispute(_transactionID, arbitrationCost);
        }
    }

    /** @dev Pay the arbitration fee to raise a dispute. To be called by the receiver. UNTRUSTED.
     *  Note that this function mirrors payArbitrationFeeBySender.
     *  @param _transactionID The index of the transaction.
     */
    function payArbitrationFeeByReceiver(uint256 _transactionID) external payable nonReentrant {
        Transaction storage transaction = transactions[_transactionID];
        require(
            transaction.status < Status.DisputeCreated,
            "Dispute has already been created or because the transaction has been executed."
        );
        require(_msgSender() == transaction.receiver, "The caller must be the receiver.");

        uint256 arbitrationCost = arbitrator.arbitrationCost(arbitratorExtraData);
        transaction.receiverFee = msg.value;

        // Require that the total paid to be at least the arbitration cost.
        require(transaction.receiverFee == arbitrationCost, "The receiver fee must cover arbitration costs.");

        transaction.lastInteraction = uint64(block.timestamp);
        // The sender still has to pay. This can also happen if he has paid, but arbitrationCost has increased.
        if (transaction.senderFee == 0) {
            transaction.status = Status.WaitingSender;
            emit HasToPayFee(_transactionID, Party.Sender);
        } else {
            // The sender has also paid the fee. We create the dispute.
            // reentrancy safe -> Status.DisputeCreated
            _raiseDispute(_transactionID, arbitrationCost);
        }
    }

    /** @dev Create a dispute. UNTRUSTED.
     *  @param _transactionID The index of the transaction.
     *  @param _arbitrationCost Amount to pay the arbitrator.
     */
    function _raiseDispute(uint256 _transactionID, uint256 _arbitrationCost) internal {
        // reentrancy check in callers
        Transaction storage transaction = transactions[_transactionID];
        transaction.status = Status.DisputeCreated; // reentrancy safe

        transaction.disputeId = arbitrator.createDispute{value: _arbitrationCost}(
            AMOUNT_OF_CHOICES,
            arbitratorExtraData
        );
        disputeIDtoTransactionID[transaction.disputeId] = _transactionID;
        emit Dispute(arbitrator, transaction.disputeId, _transactionID, _transactionID);
    }

    /** @dev Submit a reference to evidence. EVENT.
     *  @param _transactionID The index of the transaction.
     *  @param _evidence A link to an evidence using its URI.
     */
    function submitEvidence(uint256 _transactionID, string calldata _evidence) external {
        Transaction storage transaction = transactions[_transactionID];
        require(
            _msgSender() == transaction.sender || _msgSender() == transaction.receiver,
            "The caller must be the sender or the receiver."
        );
        require(transaction.status < Status.Resolved, "Must not send evidence if the dispute is resolved.");

        emit Evidence(arbitrator, _transactionID, _msgSender(), _evidence);
    }

    /** @dev Give a ruling for a dispute. Must be called by the arbitrator.
     *  The purpose of this function is to ensure that the address calling it has the right to rule on the contract.
     *  @param _disputeID ID of the dispute in the Arbitrator contract.
     *  @param _ruling Ruling given by the arbitrator. Note that 0 is reserved for "Not able/wanting to make a decision".
     */
    function rule(uint256 _disputeID, uint256 _ruling) external nonReentrant {
        require(_msgSender() == address(arbitrator), "The caller must be the arbitrator.");

        uint256 transactionID = disputeIDtoTransactionID[_disputeID];
        require(transactions[transactionID].status == Status.DisputeCreated, "The dispute has already been resolved.");

        emit Ruling(IArbitrator(_msgSender()), _disputeID, _ruling);

        // reentrancy safe -> Status.Resolved
        _executeRuling(transactionID, _ruling);
    }

    /** @dev Execute a ruling of a dispute. It reimburses the fee to the winning party.
     *  @param _transactionID The index of the transaction.
     *  @param _ruling Ruling given by the arbitrator. 1 : Reimburse the receiver. 2 : Pay the sender.
     */
    function _executeRuling(uint256 _transactionID, uint256 _ruling) internal {
        // reentrancy check in callers
        require(_ruling <= AMOUNT_OF_CHOICES, "Invalid ruling.");

        Transaction storage transaction = transactions[_transactionID];

        uint256 amount = transaction.amount;
        uint256 senderArbitrationFee = transaction.senderFee;
        uint256 receiverArbitrationFee = transaction.receiverFee;

        transaction.amount = 0;
        transaction.senderFee = 0;
        transaction.receiverFee = 0;
        transaction.status = Status.Resolved; // reentrancy safe

        uint256 feeAmount;

        // Give the arbitration fee back.
        // Note that we use send to prevent a party from blocking the execution.
        if (_ruling == SENDER_WINS) {
            _sendTo(transaction.sender, senderArbitrationFee + amount);
        } else if (_ruling == RECEIVER_WINS) {
            feeAmount = calculateFeeRecipientAmount(amount);
            _transferTo(feeRecipient, feeAmount);

            _sendTo(transaction.receiver, receiverArbitrationFee + amount - feeAmount);

            emit FeeRecipientPayment(_transactionID, feeAmount);
        } else {
            uint256 splitArbitration = senderArbitrationFee / 2;
            uint256 splitAmount = amount / 2;

            feeAmount = calculateFeeRecipientAmount(splitAmount);
            _transferTo(feeRecipient, feeAmount);

            _sendTo(transaction.sender, splitArbitration + splitAmount);
            _sendTo(transaction.receiver, splitArbitration + splitAmount - feeAmount);

            emit FeeRecipientPayment(_transactionID, feeAmount);
        }
    }

    // **************************** //
    // *     Constant getters     * //
    // **************************** //

    /** @dev Getter to know the count of transactions.
     *  @return countTransactions The count of transactions.
     */
    function getCountTransactions() external view returns (uint256 countTransactions) {
        return transactions.length;
    }

    /** @dev Get IDs for transactions where the specified address is the receiver and/or the sender.
     *  This function must be used by the UI and not by other smart contracts.
     *  Note that the complexity is O(t), where t is amount of arbitrable transactions.
     *  @param _address The specified address.
     *  @return transactionIDs The transaction IDs.
     */
    // FIXME: return calldata?
    function getTransactionIDsByAddress(address _address) external view returns (uint256[] memory transactionIDs) {
        uint256 count = 0;
        for (uint256 i = 0; i < transactions.length; i++) {
            if (transactions[i].sender == _address || transactions[i].receiver == _address) count++;
        }

        transactionIDs = new uint256[](count);

        count = 0;

        for (uint256 j = 0; j < transactions.length; j++) {
            if (transactions[j].sender == _address || transactions[j].receiver == _address) transactionIDs[count++] = j;
        }
    }
}
