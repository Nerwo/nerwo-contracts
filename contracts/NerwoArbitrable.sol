// SPDX-License-Identifier: MIT
/**
 *  @title NerwoArbitrable
 *  @author: [@eburgos, @n1c01a5, @sherpya]
 */

pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IArbitrator} from "@kleros/erc-792/contracts/IArbitrator.sol";
import {IArbitrable} from "@kleros/erc-792/contracts/IArbitrable.sol";

import {SafeTransfer} from "./SafeTransfer.sol";

contract NerwoArbitrable is Ownable, ReentrancyGuard, IArbitrable {
    using SafeTransfer for address;

    error NullAddress();
    error NoTimeout();
    error InvalidRuling();
    error InvalidCaller(address expected);
    error InvalidStatus(uint256 expected);
    error InvalidAmount();
    error InvalidTransaction();
    error InvalidToken();
    error InvalidFeeBasisPoint();

    // **************************** //
    // *    Contract variables    * //
    // **************************** //
    uint8 private constant AMOUNT_OF_CHOICES = 2;
    uint8 private constant SENDER_WINS = 1;
    uint8 private constant RECEIVER_WINS = 2;
    uint256 private constant MULTIPLIER_DIVISOR = 10000; // Divisor parameter for multipliers.

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
        uint32 lastInteraction; // Last interaction for the dispute procedure.
        address sender;
        address receiver;
        IERC20 token;
        uint256 amount;
        uint256 disputeId; // If dispute exists, the ID of the dispute.
        uint256 senderFee; // Total fees paid by the sender.
        uint256 receiverFee; // Total fees paid by the receiver.
    }

    uint256 public lastTransaction;

    IERC20[] private tokensWhitelist; // whitelisted ERC20 tokens

    struct ArbitratorData {
        IArbitrator arbitrator; // Address of the arbitrator contract.
        uint32 feeTimeout; // Time in seconds a party can take to pay arbitration fees before being considered unresponding and lose the dispute.
    }

    ArbitratorData public arbitratorData;

    struct FeeRecipientData {
        address feeRecipient; // Address which receives a share of receiver payment.
        uint16 feeRecipientBasisPoint; // The share of fee to be received by the feeRecipient, in basis points. Note that this value shouldn't exceed Divisor.
    }

    FeeRecipientData public feeRecipientData;

    mapping(uint256 => Transaction) private transactions;
    mapping(uint256 => uint256) private disputeIDtoTransactionID; // One-to-one relationship between the dispute and the transaction.

    bytes public arbitratorExtraData; // Extra data to set up the arbitration.

    // **************************** //
    // *          Events          * //
    // **************************** //

    /** @dev To be emitted when a party pays or reimburses the other.
     *  @param _transactionID The index of the transaction.
     *  @param _token The token address.
     *  @param _amount The amount paid.
     *  @param _party The party that paid.
     */
    event Payment(uint256 indexed _transactionID, address indexed _token, uint256 _amount, address indexed _party);

    /** @dev Indicate that a party has to pay a fee or would otherwise be considered as losing.
     *  @param _transactionID The index of the transaction.
     *  @param _party The party who has to pay.
     */
    event HasToPayFee(uint256 indexed _transactionID, Party _party);

    /** @dev Emitted when a transaction is created.
     *  @param _transactionID The index of the transaction.
     *  @param _sender The address of the sender.
     *  @param _receiver The address of the receiver.
     *  @param _token The token address
     *  @param _amount The initial amount in the transaction.
     */
    event TransactionCreated(
        uint256 _transactionID,
        address indexed _sender,
        address indexed _receiver,
        address indexed _token,
        uint256 _amount
    );

    /** @dev To be emitted when a fee is received by the feeRecipient.
     *  @param _transactionID The index of the transaction.
     *  @param _token The Token Address.
     *  @param _amount The amount paid.
     */
    event FeeRecipientPayment(uint256 indexed _transactionID, address indexed _token, uint256 _amount);

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

    function _requireValidTransaction(uint256 _transactionID) internal view {
        if (transactions[_transactionID].receiver == address(0)) {
            revert InvalidTransaction();
        }
    }

    modifier onlyValidTransaction(uint256 _transactionID) {
        _requireValidTransaction(_transactionID);
        _;
    }

    // **************************** //
    // *        Setters           * //
    // **************************** //

    /**
     *  @dev modifies Arbitrator - Internal function without access restriction
     *  @param _arbitrator The arbitrator of the contract.
     *  @param _arbitratorExtraData Extra data for the arbitrator.
     *  @param _feeTimeout Arbitration fee timeout for the parties.
     */
    function _setArbitrator(address _arbitrator, bytes calldata _arbitratorExtraData, uint256 _feeTimeout) internal {
        arbitratorData.arbitrator = IArbitrator(_arbitrator);
        arbitratorExtraData = _arbitratorExtraData;
        arbitratorData.feeTimeout = uint32(_feeTimeout);
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
     *  @dev modifies fee recipient and basis point - Internal function without access restriction
     *  @param _feeRecipient Address which receives a share of receiver payment.
     *  @param _feeRecipientBasisPoint The share of fee to be received by the feeRecipient,
     *         down to 2 decimal places as 550 = 5.5%
     */
    function _setFeeRecipientAndBasisPoint(address _feeRecipient, uint256 _feeRecipientBasisPoint) internal {
        uint16 feeRecipientBasisPoint = uint16(_feeRecipientBasisPoint);
        if (feeRecipientBasisPoint > MULTIPLIER_DIVISOR) {
            revert InvalidFeeBasisPoint();
        }

        feeRecipientData.feeRecipient = payable(_feeRecipient);
        feeRecipientData.feeRecipientBasisPoint = feeRecipientBasisPoint;
    }

    /**
     *  @dev modifies fee recipient and basis point - External function onlyOwner
     *  @param _feeRecipient Address which receives a share of receiver payment.
     *  @param _feeRecipientBasisPoint The share of fee to be received by the feeRecipient,
     *         down to 2 decimal places as 550 = 5.5%
     */
    function setFeeRecipientAndBasisPoint(address _feeRecipient, uint256 _feeRecipientBasisPoint) external onlyOwner {
        _setFeeRecipientAndBasisPoint(_feeRecipient, _feeRecipientBasisPoint);
    }

    function setTokensWhitelist(IERC20[] calldata _tokensWhitelist) external onlyOwner {
        _setTokensWhitelist(_tokensWhitelist);
    }

    /**
     * @dev Sets the whitelist of ERC20 tokens
     * @param _tokensWhitelist An array of ERC20 tokens
     */
    function _setTokensWhitelist(IERC20[] calldata _tokensWhitelist) internal {
        delete tokensWhitelist;
        for (uint i = 0; i < _tokensWhitelist.length; i++) {
            tokensWhitelist.push(_tokensWhitelist[i]);
        }
    }

    /** @dev Change Fee Recipient.
     *  @param _newFeeRecipient Address of the new Fee Recipient.
     */
    function changeFeeRecipient(address _newFeeRecipient) external {
        if (_msgSender() != feeRecipientData.feeRecipient) {
            revert InvalidCaller(feeRecipientData.feeRecipient);
        }

        if (_newFeeRecipient == address(0)) {
            revert NullAddress();
        }

        feeRecipientData.feeRecipient = _newFeeRecipient;
        emit FeeRecipientChanged(_msgSender(), _newFeeRecipient);
    }

    // **************************** //
    // *   Arbitrable functions   * //
    // **************************** //

    /** @dev Calculate the amount to be paid in wei according to feeRecipientBasisPoint for a particular amount.
     *  @param _amount Amount to pay in wei.
     */
    function calculateFeeRecipientAmount(uint256 _amount) public view returns (uint256) {
        return (_amount * feeRecipientData.feeRecipientBasisPoint) / MULTIPLIER_DIVISOR;
    }

    /** @dev Create a transaction.
     *  @param _token The ERC20 token contract.
     *  @param _amount The amount of tokens in this transaction.
     *  @param _receiver The recipient of the transaction.
     *  @param _metaEvidence Link to the meta-evidence.
     *  @return transactionID The index of the transaction.
     */
    function createTransaction(
        IERC20 _token,
        uint256 _amount,
        address _receiver,
        string calldata _metaEvidence
    ) external returns (uint256 transactionID) {
        if (_receiver == address(0)) {
            revert NullAddress();
        }

        if (_amount == 0) {
            revert InvalidAmount();
        }

        // Amount too low to pay fee
        // WTF: solidity, nested if consumes less gas
        if (feeRecipientData.feeRecipientBasisPoint > 0) {
            if ((_amount * feeRecipientData.feeRecipientBasisPoint) < MULTIPLIER_DIVISOR) {
                revert InvalidAmount();
            }
        }

        address sender = _msgSender();
        if (sender == _receiver) {
            revert InvalidCaller(_receiver);
        }

        IERC20 token;
        for (uint i = 0; i < tokensWhitelist.length; i++) {
            if (_token == tokensWhitelist[i]) {
                token = _token;
                break;
            }
        }

        if (address(token) == address(0)) {
            revert InvalidToken();
        }

        // first transfer tokens to the contract
        // NOTE: user must have approved the allowance
        if (!token.transferFrom(sender, address(this), _amount)) {
            revert InvalidAmount();
        }

        unchecked {
            transactionID = ++lastTransaction;
        }

        transactions[transactionID] = Transaction({
            status: Status.NoDispute,
            lastInteraction: uint32(block.timestamp),
            sender: sender,
            receiver: _receiver,
            token: token,
            amount: _amount,
            disputeId: 0,
            senderFee: 0,
            receiverFee: 0
        });

        emit MetaEvidence(transactionID, _metaEvidence);
        emit TransactionCreated(transactionID, sender, _receiver, address(_token), _amount);
    }

    /** @dev Pay receiver. To be called if the good or service is provided.
     *  @param _transactionID The index of the transaction.
     *  @param _amount Amount to pay in wei.
     */
    function pay(uint256 _transactionID, uint256 _amount) external onlyValidTransaction(_transactionID) {
        Transaction storage transaction = transactions[_transactionID];

        if (_msgSender() != transaction.sender) {
            revert InvalidCaller(transaction.sender);
        }

        if (transaction.status != Status.NoDispute) {
            revert InvalidStatus(uint256(Status.NoDispute));
        }

        if ((_amount == 0) || (transaction.amount == 0) || (_amount > transaction.amount)) {
            revert InvalidAmount();
        }

        // _amount <= transaction.amount
        unchecked {
            transaction.amount -= _amount;
        }

        uint256 feeAmount = calculateFeeRecipientAmount(_amount);
        feeRecipientData.feeRecipient.transferToken(transaction.token, feeAmount);
        emit FeeRecipientPayment(_transactionID, address(transaction.token), feeAmount);

        transaction.receiver.sendToken(transaction.token, _amount - feeAmount);
        emit Payment(_transactionID, address(transaction.token), _amount, _msgSender());
    }

    /** @dev Reimburse sender. To be called if the good or service can't be fully provided.
     *  @param _transactionID The index of the transaction.
     *  @param _amountReimbursed Amount to reimburse in wei.
     */
    function reimburse(
        uint256 _transactionID,
        uint256 _amountReimbursed
    ) external onlyValidTransaction(_transactionID) {
        Transaction storage transaction = transactions[_transactionID];

        if (_msgSender() != transaction.receiver) {
            revert InvalidCaller(transaction.receiver);
        }

        if (transaction.status != Status.NoDispute) {
            revert InvalidStatus(uint256(Status.NoDispute));
        }

        if ((_amountReimbursed == 0) || (transaction.amount == 0) || (_amountReimbursed > transaction.amount)) {
            revert InvalidAmount();
        }

        // _amountReimbursed <= transaction.amount
        unchecked {
            transaction.amount -= _amountReimbursed;
        }
        transaction.sender.sendToken(transaction.token, _amountReimbursed);
        emit Payment(_transactionID, address(transaction.token), _amountReimbursed, _msgSender());
    }

    /** @dev Reimburse sender if receiver fails to pay the fee.
     *  @param _transactionID The index of the transaction.
     */
    function timeOutBySender(uint256 _transactionID) external onlyValidTransaction(_transactionID) {
        Transaction storage transaction = transactions[_transactionID];

        if (transaction.status != Status.WaitingReceiver) {
            revert InvalidStatus(uint256(Status.WaitingReceiver));
        }

        if (block.timestamp - transaction.lastInteraction < arbitratorData.feeTimeout) {
            revert NoTimeout();
        }

        _executeRuling(_transactionID, SENDER_WINS);
    }

    /** @dev Pay receiver if sender fails to pay the fee.
     *  @param _transactionID The index of the transaction.
     */
    function timeOutByReceiver(uint256 _transactionID) external onlyValidTransaction(_transactionID) {
        Transaction storage transaction = transactions[_transactionID];

        if (transaction.status != Status.WaitingSender) {
            revert InvalidStatus(uint256(Status.WaitingSender));
        }

        if (block.timestamp - transaction.lastInteraction < arbitratorData.feeTimeout) {
            revert NoTimeout();
        }

        _executeRuling(_transactionID, RECEIVER_WINS);
    }

    /** @dev Pay the arbitration fee to raise a dispute. To be called by the sender. UNTRUSTED.
     *  Note that the arbitrator can have createDispute throw, which will make this function throw and therefore lead to a party being timed-out.
     *  This is not a vulnerability as the arbitrator can rule in favor of one party anyway.
     *  @param _transactionID The index of the transaction.
     */
    function payArbitrationFeeBySender(uint256 _transactionID) external payable onlyValidTransaction(_transactionID) {
        Transaction storage transaction = transactions[_transactionID];

        if (_msgSender() != transaction.sender) {
            revert InvalidCaller(transaction.sender);
        }

        if (transaction.status >= Status.DisputeCreated) {
            revert InvalidStatus(uint256(Status.DisputeCreated));
        }

        uint256 _arbitrationCost = arbitratorData.arbitrator.arbitrationCost(arbitratorExtraData);

        if (msg.value != _arbitrationCost) {
            revert InvalidAmount();
        }

        transaction.senderFee = msg.value;
        transaction.lastInteraction = uint32(block.timestamp);

        // The receiver still has to pay. This can also happen if he has paid,
        // but arbitrationCost has increased.
        if (transaction.receiverFee == 0) {
            transaction.status = Status.WaitingReceiver;
            emit HasToPayFee(_transactionID, Party.Receiver);
        } else {
            // The receiver has also paid the fee. We create the dispute.
            _raiseDispute(_transactionID, _arbitrationCost);
        }
    }

    /** @dev Pay the arbitration fee to raise a dispute. To be called by the receiver. UNTRUSTED.
     *  Note that this function mirrors payArbitrationFeeBySender.
     *  @param _transactionID The index of the transaction.
     */
    function payArbitrationFeeByReceiver(uint256 _transactionID) external payable onlyValidTransaction(_transactionID) {
        Transaction storage transaction = transactions[_transactionID];

        if (_msgSender() != transaction.receiver) {
            revert InvalidCaller(transaction.receiver);
        }

        if (transaction.status >= Status.DisputeCreated) {
            revert InvalidStatus(uint256(Status.DisputeCreated));
        }

        uint256 _arbitrationCost = arbitratorData.arbitrator.arbitrationCost(arbitratorExtraData);

        if (msg.value != _arbitrationCost) {
            revert InvalidAmount();
        }

        transaction.receiverFee = msg.value;
        transaction.lastInteraction = uint32(block.timestamp);

        // The sender still has to pay. This can also happen if he has paid,
        // but arbitrationCost has increased.
        if (transaction.senderFee == 0) {
            transaction.status = Status.WaitingSender;
            emit HasToPayFee(_transactionID, Party.Sender);
        } else {
            // The sender has also paid the fee. We create the dispute.
            _raiseDispute(_transactionID, _arbitrationCost);
        }
    }

    /** @dev Create a dispute. UNTRUSTED.
     *  @param _transactionID The index of the transaction.
     *  @param _arbitrationCost Amount to pay the arbitrator.
     */
    function _raiseDispute(uint256 _transactionID, uint256 _arbitrationCost) internal {
        Transaction storage transaction = transactions[_transactionID];
        transaction.status = Status.DisputeCreated;

        transaction.disputeId = arbitratorData.arbitrator.createDispute{value: _arbitrationCost}(
            AMOUNT_OF_CHOICES,
            arbitratorExtraData
        );

        disputeIDtoTransactionID[transaction.disputeId] = _transactionID;

        emit Dispute(arbitratorData.arbitrator, transaction.disputeId, _transactionID, _transactionID);
    }

    /** @dev Submit a reference to evidence. EVENT.
     *  @param _transactionID The index of the transaction.
     *  @param _evidence A link to an evidence using its URI.
     */
    function submitEvidence(
        uint256 _transactionID,
        string calldata _evidence
    ) external onlyValidTransaction(_transactionID) {
        Transaction storage transaction = transactions[_transactionID];

        if (_msgSender() != transaction.sender && _msgSender() != transaction.receiver) {
            revert InvalidCaller(address(0));
        }

        if (transaction.status >= Status.Resolved) {
            revert InvalidStatus(uint256(Status.Resolved));
        }

        emit Evidence(arbitratorData.arbitrator, _transactionID, _msgSender(), _evidence);
    }

    /** @dev Give a ruling for a dispute. Must be called by the arbitrator.
     *  The purpose of this function is to ensure that the address calling
     *  it has the right to rule on the contract.
     *  @param _disputeID ID of the dispute in the Arbitrator contract.
     *  @param _ruling Ruling given by the arbitrator.
     *                 Note that 0 is reserved for "Not able/wanting to make a decision".
     */
    function rule(uint256 _disputeID, uint256 _ruling) external override {
        if (_msgSender() != address(arbitratorData.arbitrator)) {
            revert InvalidCaller(address(arbitratorData.arbitrator));
        }

        if (_ruling > AMOUNT_OF_CHOICES) {
            revert InvalidRuling();
        }

        uint256 transactionID = disputeIDtoTransactionID[_disputeID];
        _requireValidTransaction(transactionID);

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
    function _executeRuling(uint256 _transactionID, uint256 _ruling) internal nonReentrant {
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
            transaction.sender.sendToken(transaction.token, amount);
            transaction.sender.sendTo(senderArbitrationFee);
        } else if (_ruling == RECEIVER_WINS) {
            feeAmount = calculateFeeRecipientAmount(amount);
            feeRecipientData.feeRecipient.transferToken(transaction.token, feeAmount);
            emit FeeRecipientPayment(_transactionID, address(transaction.token), feeAmount);

            transaction.receiver.sendToken(transaction.token, amount - feeAmount);
            transaction.receiver.sendTo(receiverArbitrationFee);
        } else {
            uint256 splitArbitration = senderArbitrationFee / 2;
            uint256 splitAmount = amount / 2;

            feeAmount = calculateFeeRecipientAmount(splitAmount);
            feeRecipientData.feeRecipient.transferToken(transaction.token, feeAmount);
            emit FeeRecipientPayment(_transactionID, address(transaction.token), feeAmount);

            // In the case of an uneven token amount, one basic token unit can be burnt.
            transaction.sender.sendToken(transaction.token, splitAmount);
            transaction.receiver.sendToken(transaction.token, splitAmount - feeAmount);

            transaction.sender.sendTo(splitArbitration);
            transaction.receiver.sendTo(splitArbitration);
        }
    }

    // **************************** //
    // *   Utils for frontends    * //
    // **************************** //

    /**
     * @dev Get transaction by id
     * @return transaction
     */
    function getTransaction(
        uint256 _transactionID
    ) external view onlyValidTransaction(_transactionID) returns (Transaction memory) {
        return transactions[_transactionID];
    }

    /**
     * @dev Get supported ERC20 tokens
     * @return tokens array of addresses of supported tokens
     */
    function getSupportedTokens() external view returns (IERC20[] memory) {
        return tokensWhitelist;
    }

    /**
     * @dev Ask arbitrator for abitration cost
     * @return cost Amount to be paid.
     */
    function arbitrationCost() external view returns (uint256 cost) {
        cost = arbitratorData.arbitrator.arbitrationCost(arbitratorExtraData);
    }
}