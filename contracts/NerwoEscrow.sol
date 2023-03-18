// SPDX-License-Identifier: MIT
/**
 *  @title EscrowWithDispute
 *  @author: [@eburgos, @n1c01a5, @sherpya]
 *
 *  @notice This contract implements an escrow system with dispute resolution, allowing secure transactions
 * between a sender and a receiver. The contract holds funds on behalf of the sender until the transaction
 * is completed or a dispute arises. If a dispute occurs, an external arbitrator determines the outcome.
 *
 * The main features of the contract are:
 * 1. Create transactions: The sender initializes a transaction by providing details such as the receiver's
 *    address, the transaction amount, and any associated fees.
 * 2. Make payments: The sender can pay the receiver if the goods or services are provided as expected.
 * 3. Reimbursements: The receiver can reimburse the sender if the goods or services cannot be fully provided.
 * 4. Execute transactions: If the timeout has passed, the receiver can execute the transaction and receive
 *    the transaction amount.
 * 5. Timeouts: Both the sender and receiver can trigger a timeout if the counterparty fails to pay the arbitration fee.
 * 6. Raise disputes and handle arbitration fees: Both parties can raise disputes and pay arbitration fees. The
 *    contract ensures that both parties pay the fees before raising a dispute.
 * 7. Submit evidence: Both parties can submit evidence to support their case during a dispute.
 * 8. Arbitrator ruling: The external arbitrator can provide a ruling to resolve the dispute. The ruling is
 *    executed by the contract, which redistributes the funds accordingly.
 *
 * The contract follows best practices for security, gas optimization, and error handling. It uses Solidity's
 * custom errors, nonReentrant modifier, and events for better tracking and debugging.
 */

pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {IArbitrator} from "./kleros/IArbitrator.sol";
import {IArbitrable} from "./kleros/IArbitrable.sol";

error NullAddress();
error TransferFailed(address recipient, uint256 amount, bytes data);
error NoTimeout();
error InvalidRuling();
error InvalidCaller(address expected);
error InvalidStatus(uint256 expected);
error InvalidAmount(uint256 amount);
error InvalidPriceThresolds();
error NoLostFunds();

contract NerwoEscrow is Ownable, ReentrancyGuard, IArbitrable, ERC165 {
    using SafeCast for uint256;

    // **************************** //
    // *    Contract variables    * //
    // **************************** //
    uint8 private constant AMOUNT_OF_CHOICES = 2;
    uint8 private constant SENDER_WINS = 1;
    uint8 private constant RECEIVER_WINS = 2;

    enum Party {
        Sender,
        Receiver
    }

    struct PriceThreshold {
        uint256 maxPrice;
        uint256 feeBasisPoint;
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
        uint32 timeoutPayment; // Time in seconds after which the transaction can be automatically executed if not disputed.
        uint32 lastInteraction; // Last interaction for the dispute procedure.
        uint32 feeBasisPoint;
        uint256 amount;
        uint256 disputeId; // If dispute exists, the ID of the dispute.
        uint256 senderFee; // Total fees paid by the sender.
        uint256 receiverFee; // Total fees paid by the receiver.
    }

    PriceThreshold[] public priceThresholds;

    Transaction[] public transactions;
    bytes public arbitratorExtraData; // Extra data to set up the arbitration.
    IArbitrator public arbitrator; // Address of the arbitrator contract.

    uint256 public feeTimeout; // Time in seconds a party can take to pay arbitration fees before being considered unresponding and lose the dispute.
    uint256 public minimalAmount;

    address payable public feeRecipient; // Address which receives a share of receiver payment.

    uint256 public lostFunds; // failed to receive funds, e.g. error in _sendTo()

    mapping(uint256 => uint256) private disputeIDtoTransactionID; // One-to-one relationship between the dispute and the transaction.

    // **************************** //
    // *          Events          * //
    // **************************** //

    /** @dev To be emitted when a party pays or reimburses the other.
     *  @param _transactionID The index of the transaction.
     *  @param _amount The amount paid.
     *  @param _party The party that paid.
     */
    event Payment(uint256 indexed _transactionID, uint256 _amount, address indexed _party);

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
    event SendFailed(address indexed recipient, uint256 amount, bytes data);

    /** @dev To be emitted when the owner withdraw lost funds
     *  @param recipient The owner at the moment of withdrawal
     *  @param amount The amount
     */
    event FundsRecovered(address indexed recipient, uint256 amount);

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IArbitrable).interfaceId || super.supportsInterface(interfaceId);
    }

    // **************************** //
    // *    Arbitrable functions  * //
    // *    Modifying the state   * //
    // **************************** //

    /** @dev constructor
     *  @param _owner The initial owner
     *  @param _arbitrator The arbitrator of the contract.
     *  @param _arbitratorExtraData Extra data for the arbitrator.
     *  @param _feeTimeout Arbitration fee timeout for the parties.
     *  @param _feeRecipient Address which receives a share of receiver payment.
     *  @param _priceThresholds List of tuple to calculate fee amount based on price
     */
    constructor(
        address _owner,
        address _arbitrator,
        bytes memory _arbitratorExtraData,
        uint256 _feeTimeout,
        uint256 _minimalAmount,
        address _feeRecipient,
        PriceThreshold[] memory _priceThresholds
    ) {
        _setArbitrator(_arbitrator, _arbitratorExtraData, _feeTimeout);
        _setMinimalAmount(_minimalAmount);
        _setFeeRecipient(_feeRecipient);
        _setPriceThresholds(_priceThresholds);
        _transferOwnership(_owner);
    }

    /**
     *  @dev modifies Arbitrator - Internal function without access restriction
     *  @param _arbitrator The arbitrator of the contract.
     *  @param _arbitratorExtraData Extra data for the arbitrator.
     *  @param _feeTimeout Arbitration fee timeout for the parties.
     */
    function _setArbitrator(address _arbitrator, bytes memory _arbitratorExtraData, uint256 _feeTimeout) internal {
        arbitrator = IArbitrator(_arbitrator);
        arbitratorExtraData = _arbitratorExtraData;
        feeTimeout = _feeTimeout;
    }

    /**
     *  @dev modifies Arbitrator - External function onlyOwner
     *  @param _arbitrator The arbitrator of the contract.
     *  @param _arbitratorExtraData Extra data for the arbitrator.
     *  @param _feeTimeout Arbitration fee timeout for the parties.
     */
    function setArbitrator(
        address _arbitrator,
        bytes calldata _arbitratorExtraData,
        uint256 _feeTimeout
    ) external onlyOwner {
        _setArbitrator(_arbitrator, _arbitratorExtraData, _feeTimeout);
    }

    /**
     * @dev Modifies the minimum amount that can be sent in a transaction.
     * @param _minimalAmount The new minimum amount.
     */
    function _setMinimalAmount(uint256 _minimalAmount) internal {
        if (_minimalAmount == 0) {
            revert InvalidAmount(0);
        }
        minimalAmount = _minimalAmount;
    }

    /**
     * @dev Modifies the minimum amount that can be sent in a transaction. Only the contract owner can call this function.
     * @param _minimalAmount The new minimum amount.
     */
    function setMinimalAmount(uint256 _minimalAmount) external onlyOwner {
        _setMinimalAmount(_minimalAmount);
    }

    /**
     *  @dev modifies fee recipient and basis point - Internal function without access restriction
     *  @param _feeRecipient Address which receives a share of receiver payment.
     */
    function _setFeeRecipient(address _feeRecipient) internal {
        feeRecipient = payable(_feeRecipient);
    }

    /**
     *  @dev modifies fee recipient and basis point - External function onlyOwner
     *  @param _feeRecipient Address which receives a share of receiver payment.
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        _setFeeRecipient(_feeRecipient);
    }

    /**
     * @dev Sets the price thresholds array - Internal function without access restriction
     * @param _priceThresholds An array of PriceThreshold structs to set as the new price thresholds.
     */
    function _setPriceThresholds(PriceThreshold[] memory _priceThresholds) internal {
        if (_priceThresholds.length == 0) {
            revert InvalidPriceThresolds();
        }

        delete priceThresholds;
        for (uint i = 0; i < _priceThresholds.length; i++) {
            priceThresholds.push(_priceThresholds[i]);
        }
    }

    /**
     * @dev Sets the price thresholds array - External function onlyOwner
     * @param _priceThresholds An array of PriceThreshold structs to set as the new price thresholds.
     */
    function setPriceThresholds(PriceThreshold[] calldata _priceThresholds) external onlyOwner {
        _setPriceThresholds(_priceThresholds);
    }

    /**
     * @dev Returns the current ETH balance of the contract.
     * @return The current balance of the contract.
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function _findFeeBasisPoint(uint256 _amount) internal view returns (uint256 feeBasisPoint) {
        for (uint i = 0; i < priceThresholds.length; i++) {
            feeBasisPoint = priceThresholds[i].feeBasisPoint;
            if (_amount <= priceThresholds[i].maxPrice) {
                return feeBasisPoint;
            }
        }

        if (feeBasisPoint == 0) {
            revert InvalidPriceThresolds();
        }
    }

    /** @dev Calculate the amount to be paid in wei according to feeRecipientBasisPoint for a particular amount.
     *  @param _amount Amount to pay in wei.
     */
    function calculateFeeRecipientAmount(uint256 _amount) external view returns (uint256) {
        return (_amount * _findFeeBasisPoint(_amount)) / 10000;
    }

    function _calculateFeeAmount(uint256 _amount, uint32 _feeBasisPoint) internal pure returns (uint256) {
        return (_amount * _feeBasisPoint) / 10000;
    }

    /** @dev Change Fee Recipient.
     *  @param _newFeeRecipient Address of the new Fee Recipient.
     */
    function changeFeeRecipient(address _newFeeRecipient) external {
        if (_msgSender() != feeRecipient) {
            revert InvalidCaller(feeRecipient);
        }

        if (_newFeeRecipient == address(0)) {
            revert NullAddress();
        }

        feeRecipient = payable(_newFeeRecipient);
        emit FeeRecipientChanged(_msgSender(), _newFeeRecipient);
    }

    /** @dev Send to recipent, emit a log when fails
     *  @param target To address to send to
     *  @param amount Transaction amount
     */
    function _sendTo(address payable target, uint256 amount) internal {
        (bool success, bytes memory data) = target.call{value: amount}("");
        if (!success) {
            emit SendFailed(target, amount, data);
            lostFunds += amount;
        }
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

    /** @dev Withdraw lost founds (when _sendTo() fails) */
    function withdrawLostFunds() external onlyOwner nonReentrant {
        if (lostFunds == 0) {
            revert NoLostFunds();
        }

        uint256 amount = lostFunds;
        lostFunds = 0;

        _transferTo(payable(_msgSender()), amount);
        emit FundsRecovered(_msgSender(), amount);
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
        if (_receiver == address(0)) {
            revert NullAddress();
        }

        if (msg.value < minimalAmount) {
            revert InvalidAmount(minimalAmount);
        }

        if (_msgSender() == _receiver) {
            revert InvalidCaller(_receiver);
        }

        transactionID = transactions.length;

        transactions.push(
            Transaction({
                sender: payable(_msgSender()),
                receiver: payable(_receiver),
                amount: msg.value,
                feeBasisPoint: _findFeeBasisPoint(msg.value).toUint32(),
                timeoutPayment: _timeoutPayment.toUint32(),
                disputeId: 0,
                senderFee: 0,
                receiverFee: 0,
                lastInteraction: uint32(block.timestamp),
                status: Status.NoDispute
            })
        );

        emit MetaEvidence(transactionID, _metaEvidence);
        emit TransactionCreated(transactionID, _msgSender(), _receiver, msg.value);
    }

    /** @dev Pay receiver. To be called if the good or service is provided.
     *  @param _transactionID The index of the transaction.
     *  @param _amount Amount to pay in wei.
     */
    function pay(uint256 _transactionID, uint256 _amount) external nonReentrant {
        Transaction storage transaction = transactions[_transactionID];

        if (_msgSender() != transaction.sender) {
            revert InvalidCaller(transaction.sender);
        }

        if (transaction.status != Status.NoDispute) {
            revert InvalidStatus(uint256(Status.NoDispute));
        }

        if ((_amount == 0) || (transaction.amount == 0) || (_amount > transaction.amount)) {
            revert InvalidAmount(transaction.amount);
        }

        transaction.amount -= _amount;

        uint256 feeAmount = _calculateFeeAmount(_amount, transaction.feeBasisPoint);
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

        if (_msgSender() != transaction.receiver) {
            revert InvalidCaller(transaction.receiver);
        }

        if (transaction.status != Status.NoDispute) {
            revert InvalidStatus(uint256(Status.NoDispute));
        }

        if ((_amountReimbursed == 0) || (transaction.amount == 0) || (_amountReimbursed > transaction.amount)) {
            revert InvalidAmount(transaction.amount);
        }

        transaction.amount -= _amountReimbursed;
        _sendTo(transaction.sender, _amountReimbursed);

        emit Payment(_transactionID, _amountReimbursed, _msgSender());
    }

    /** @dev Transfer the transaction's amount to the receiver if the timeout has passed.
     *  @param _transactionID The index of the transaction.
     */
    function executeTransaction(uint256 _transactionID) external nonReentrant {
        Transaction storage transaction = transactions[_transactionID];

        if (transaction.status != Status.NoDispute) {
            revert InvalidStatus(uint256(Status.NoDispute));
        }

        if (block.timestamp - transaction.lastInteraction < transaction.timeoutPayment) {
            revert NoTimeout();
        }

        if (transaction.amount == 0) {
            revert InvalidAmount(0);
        }

        transaction.status = Status.Resolved;

        uint256 amount = transaction.amount;
        transaction.amount = 0;

        uint256 feeAmount = _calculateFeeAmount(amount, transaction.feeBasisPoint);
        _transferTo(feeRecipient, feeAmount);

        _sendTo(transaction.receiver, amount - feeAmount);

        emit FeeRecipientPayment(_transactionID, feeAmount);
    }

    /** @dev Reimburse sender if receiver fails to pay the fee.
     *  @param _transactionID The index of the transaction.
     */
    function timeOutBySender(uint256 _transactionID) external nonReentrant {
        Transaction storage transaction = transactions[_transactionID];

        if (transaction.status != Status.WaitingReceiver) {
            revert InvalidStatus(uint256(Status.WaitingReceiver));
        }

        if (block.timestamp - transaction.lastInteraction < feeTimeout) {
            revert NoTimeout();
        }

        _executeRuling(_transactionID, SENDER_WINS);
    }

    /** @dev Pay receiver if sender fails to pay the fee.
     *  @param _transactionID The index of the transaction.
     */
    function timeOutByReceiver(uint256 _transactionID) external nonReentrant {
        Transaction storage transaction = transactions[_transactionID];

        if (transaction.status != Status.WaitingSender) {
            revert InvalidStatus(uint256(Status.WaitingSender));
        }

        if (block.timestamp - transaction.lastInteraction < feeTimeout) {
            revert NoTimeout();
        }

        _executeRuling(_transactionID, RECEIVER_WINS);
    }

    /** @dev Pay the arbitration fee to raise a dispute. To be called by the sender. UNTRUSTED.
     *  Note that the arbitrator can have createDispute throw, which will make this function throw and therefore lead to a party being timed-out.
     *  This is not a vulnerability as the arbitrator can rule in favor of one party anyway.
     *  @param _transactionID The index of the transaction.
     */
    function payArbitrationFeeBySender(uint256 _transactionID) external payable nonReentrant {
        Transaction storage transaction = transactions[_transactionID];

        if (_msgSender() != transaction.sender) {
            revert InvalidCaller(transaction.sender);
        }

        if (transaction.status >= Status.DisputeCreated) {
            revert InvalidStatus(uint256(Status.DisputeCreated));
        }

        uint256 arbitrationCost = arbitrator.arbitrationCost(arbitratorExtraData);

        if (msg.value != arbitrationCost) {
            revert InvalidAmount(arbitrationCost);
        }

        transaction.senderFee = msg.value;
        transaction.lastInteraction = uint32(block.timestamp);

        // The receiver still has to pay. This can also happen if he has paid, but arbitrationCost has increased.
        if (transaction.receiverFee == 0) {
            transaction.status = Status.WaitingReceiver;
            emit HasToPayFee(_transactionID, Party.Receiver);
        } else {
            // The receiver has also paid the fee. We create the dispute.
            _raiseDispute(_transactionID, arbitrationCost);
        }
    }

    /** @dev Pay the arbitration fee to raise a dispute. To be called by the receiver. UNTRUSTED.
     *  Note that this function mirrors payArbitrationFeeBySender.
     *  @param _transactionID The index of the transaction.
     */
    function payArbitrationFeeByReceiver(uint256 _transactionID) external payable nonReentrant {
        Transaction storage transaction = transactions[_transactionID];

        if (_msgSender() != transaction.receiver) {
            revert InvalidCaller(transaction.receiver);
        }

        if (transaction.status >= Status.DisputeCreated) {
            revert InvalidStatus(uint256(Status.DisputeCreated));
        }

        uint256 arbitrationCost = arbitrator.arbitrationCost(arbitratorExtraData);

        if (msg.value != arbitrationCost) {
            revert InvalidAmount(arbitrationCost);
        }

        transaction.receiverFee = msg.value;
        transaction.lastInteraction = uint32(block.timestamp);

        // The sender still has to pay. This can also happen if he has paid, but arbitrationCost has increased.
        if (transaction.senderFee == 0) {
            transaction.status = Status.WaitingSender;
            emit HasToPayFee(_transactionID, Party.Sender);
        } else {
            // The sender has also paid the fee. We create the dispute.
            _raiseDispute(_transactionID, arbitrationCost);
        }
    }

    /** @dev Create a dispute. UNTRUSTED.
     *  @param _transactionID The index of the transaction.
     *  @param _arbitrationCost Amount to pay the arbitrator.
     */
    function _raiseDispute(uint256 _transactionID, uint256 _arbitrationCost) internal {
        Transaction storage transaction = transactions[_transactionID];
        transaction.status = Status.DisputeCreated;

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

        if (_msgSender() != transaction.sender && _msgSender() != transaction.receiver) {
            revert InvalidCaller(address(0));
        }

        if (transaction.status >= Status.Resolved) {
            revert InvalidStatus(uint64(Status.Resolved));
        }

        emit Evidence(arbitrator, _transactionID, _msgSender(), _evidence);
    }

    /** @dev Give a ruling for a dispute. Must be called by the arbitrator.
     *  The purpose of this function is to ensure that the address calling it has the right to rule on the contract.
     *  @param _disputeID ID of the dispute in the Arbitrator contract.
     *  @param _ruling Ruling given by the arbitrator. Note that 0 is reserved for "Not able/wanting to make a decision".
     */
    function rule(uint256 _disputeID, uint256 _ruling) external override nonReentrant {
        if (_msgSender() != address(arbitrator)) {
            revert InvalidCaller(address(arbitrator));
        }

        uint256 transactionID = disputeIDtoTransactionID[_disputeID];
        if (transactions[transactionID].status != Status.DisputeCreated) {
            revert InvalidStatus(uint256(Status.DisputeCreated));
        }

        emit Ruling(IArbitrator(_msgSender()), _disputeID, _ruling);

        _executeRuling(transactionID, _ruling);
    }

    /** @dev Execute a ruling of a dispute. It reimburses the fee to the winning party.
     *  @param _transactionID The index of the transaction.
     *  @param _ruling Ruling given by the arbitrator. 1 : Reimburse the receiver. 2 : Pay the sender.
     */
    function _executeRuling(uint256 _transactionID, uint256 _ruling) internal {
        if (_ruling > AMOUNT_OF_CHOICES) {
            revert InvalidRuling();
        }

        Transaction storage transaction = transactions[_transactionID];

        uint256 amount = transaction.amount;
        uint256 senderArbitrationFee = transaction.senderFee;
        uint256 receiverArbitrationFee = transaction.receiverFee;

        transaction.amount = 0;
        transaction.senderFee = 0;
        transaction.receiverFee = 0;
        transaction.status = Status.Resolved;

        uint256 feeAmount;

        // Give the arbitration fee back.
        // Note that we use send to prevent a party from blocking the execution.
        if (_ruling == SENDER_WINS) {
            _sendTo(transaction.sender, senderArbitrationFee + amount);
        } else if (_ruling == RECEIVER_WINS) {
            feeAmount = _calculateFeeAmount(amount, transaction.feeBasisPoint);
            _transferTo(feeRecipient, feeAmount);

            _sendTo(transaction.receiver, receiverArbitrationFee + amount - feeAmount);

            emit FeeRecipientPayment(_transactionID, feeAmount);
        } else {
            uint256 splitArbitration = senderArbitrationFee / 2;
            uint256 splitAmount = amount / 2;

            feeAmount = _calculateFeeAmount(splitAmount, transaction.feeBasisPoint);
            _transferTo(feeRecipient, feeAmount);

            _sendTo(transaction.sender, splitArbitration + splitAmount);
            _sendTo(transaction.receiver, splitArbitration + splitAmount - feeAmount);

            emit FeeRecipientPayment(_transactionID, feeAmount);
        }
    }
}
