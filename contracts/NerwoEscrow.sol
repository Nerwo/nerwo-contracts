// SPDX-License-Identifier: MIT
/**
 *  @title NerwoEscrow
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
 */

pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IArbitrator} from "@kleros/erc-792/contracts/IArbitrator.sol";

import {IArbitrableProxy} from "./IArbitrableProxy.sol";
import {SafeTransfer} from "./SafeTransfer.sol";

contract NerwoEscrow is Ownable, Initializable, ReentrancyGuard {
    using SafeTransfer for address;

    error NullAddress();
    error NoTimeout();
    error InvalidCaller(address expected);
    error InvalidStatus(uint256 expected);
    error InvalidAmount();
    error InvalidTransaction();
    error InvalidToken();
    error InvalidFeeBasisPoint();
    error NotRuled();

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
        uint256 disputeID; // If dispute exists, the ID of the dispute.
        uint256 senderFee; // Total fees paid by the sender.
        uint256 receiverFee; // Total fees paid by the receiver.
    }

    uint256 public lastTransaction;

    IERC20[] private tokensWhitelist; // whitelisted ERC20 tokens

    struct ArbitratorData {
        IArbitrator arbitrator; // Address of the arbitrator contract.
        IArbitrableProxy proxy; // Address of the arbitrator proxy contract.
        uint32 feeTimeout; // Time in seconds a party can take to pay arbitration fees before being considered unresponding and lose the dispute.
    }

    ArbitratorData public arbitratorData;

    struct FeeRecipientData {
        address feeRecipient; // Address which receives a share of receiver payment.
        uint16 feeRecipientBasisPoint; // The share of fee to be received by the feeRecipient, in basis points. Note that this value shouldn't exceed Divisor.
    }

    FeeRecipientData public feeRecipientData;

    mapping(uint256 => Transaction) private transactions;

    bytes public arbitratorExtraData; // Extra data to set up the arbitration.
    string public metaEvidenceURI;

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

    function _requireValidTransaction(uint256 _transactionID) internal view {
        if (transactions[_transactionID].receiver == address(0)) {
            revert InvalidTransaction();
        }
    }

    modifier onlyValidTransaction(uint256 _transactionID) {
        _requireValidTransaction(_transactionID);
        _;
    }

    /** @dev contructor
     *  @notice set ownership before calling initialize to avoid front running in deployment
     *  @notice since we are using hardhat-deploy deterministic deployment the sender
     *  @notice is 0x4e59b44847b379578588920ca78fbf26c0b4956c
     */
    constructor() {
        /* solhint-disable avoid-tx-origin */
        _transferOwnership(tx.origin);
    }

    /** @dev initialize (deferred constructor)
     *  @param _owner The initial owner
     *  @param _arbitrator The arbitrator of the contract.
     *  @param _arbitratorProxy The arbitrator proxy of the contract.
     *  @param _arbitratorExtraData Extra data for the arbitrator.
     *  @param _feeTimeout Arbitration fee timeout for the parties.
     *  @param _feeRecipient Address which receives a share of receiver payment.
     *  @param _feeRecipientBasisPoint The share of fee to be received by the feeRecipient,
     *                                 down to 2 decimal places as 550 = 5.5%
     *  @param _tokensWhitelist List of whitelisted ERC20 tokens
     */
    function initialize(
        address _owner,
        address _arbitrator,
        address _arbitratorProxy,
        bytes calldata _arbitratorExtraData,
        uint256 _feeTimeout,
        address _feeRecipient,
        uint256 _feeRecipientBasisPoint,
        IERC20[] calldata _tokensWhitelist
    ) external onlyOwner initializer {
        _transferOwnership(_owner);
        _setArbitratorData(_arbitrator, _arbitratorProxy, _arbitratorExtraData, _feeTimeout);
        _setFeeRecipientAndBasisPoint(_feeRecipient, _feeRecipientBasisPoint);
        _setTokensWhitelist(_tokensWhitelist);
    }

    // **************************** //
    // *        Setters           * //
    // **************************** //

    /**
     *  @dev modifies Arbitrator - Internal function without access restriction
     *  @param _arbitrator The arbitrator of the contract.
     *  @param _arbitratorProxy The arbitrator proxy of the contract.
     *  @param _arbitratorExtraData Extra data for the arbitrator.
     *  @param _feeTimeout Arbitration fee timeout for the parties.
     */
    function _setArbitratorData(
        address _arbitrator,
        address _arbitratorProxy,
        bytes calldata _arbitratorExtraData,
        uint256 _feeTimeout
    ) internal {
        arbitratorData.arbitrator = IArbitrator(_arbitrator);
        arbitratorData.proxy = IArbitrableProxy(_arbitratorProxy);
        arbitratorExtraData = _arbitratorExtraData;
        arbitratorData.feeTimeout = uint32(_feeTimeout);
    }

    /**
     *  @dev modifies Arbitrator Data - External function onlyOwner
     *  @param _arbitrator The arbitrator of the contract.
     *  @param _arbitratorProxy The arbitrator proxy of the contract.
     *  @param _arbitratorExtraData Extra data for the arbitrator.
     *  @param _feeTimeout Arbitration fee timeout for the parties.
     */
    function setArbitratorData(
        address _arbitrator,
        address _arbitratorProxy,
        bytes calldata _arbitratorExtraData,
        uint256 _feeTimeout
    ) external onlyOwner {
        _setArbitratorData(_arbitrator, _arbitratorProxy, _arbitratorExtraData, _feeTimeout);
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
     * @dev set platform metaEvedence IPFS URI
     * @param _metaEvidenceURI The URI pointing to metaEvidence.json
     */
    function setMetaEvidenceURI(string calldata _metaEvidenceURI) external onlyOwner {
        _setMetaEvidenceURI(_metaEvidenceURI);
    }

    function _setMetaEvidenceURI(string calldata _metaEvidenceURI) internal {
        metaEvidenceURI = _metaEvidenceURI;
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
        unchecked {
            delete tokensWhitelist;
            for (uint i = 0; i < _tokensWhitelist.length; i++) {
                tokensWhitelist.push(_tokensWhitelist[i]);
            }
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
     *  @return transactionID The index of the transaction.
     */
    function createTransaction(
        IERC20 _token,
        uint256 _amount,
        address _receiver
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
        unchecked {
            for (uint i = 0; i < tokensWhitelist.length; i++) {
                if (_token == tokensWhitelist[i]) {
                    token = _token;
                    break;
                }
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
            disputeID: 0,
            senderFee: 0,
            receiverFee: 0
        });

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

        transaction.disputeID = arbitratorData.proxy.createDispute{value: _arbitrationCost}(
            arbitratorExtraData,
            metaEvidenceURI,
            AMOUNT_OF_CHOICES
        );
    }

    /** @dev Accept ruling for a dispute.
     *  @param _transactionID the transaction the dispute was created from.
     */
    function acceptRuling(uint256 _transactionID) external onlyValidTransaction(_transactionID) {
        Transaction storage transaction = transactions[_transactionID];

        if (transaction.status != Status.DisputeCreated) {
            revert InvalidStatus(uint256(Status.DisputeCreated));
        }

        (, bool isRuled, uint256 ruling, ) = arbitratorData.proxy.disputes(transaction.disputeID);

        if (!isRuled) {
            revert NotRuled();
        }

        _executeRuling(_transactionID, ruling);
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
        address sender = transaction.sender;
        address receiver = transaction.receiver;

        // Give the arbitration fee back.
        // Note that we use send to prevent a party from blocking the execution.
        if (_ruling == SENDER_WINS) {
            sender.sendToken(transaction.token, amount);
            sender.sendTo(senderArbitrationFee);
        } else if (_ruling == RECEIVER_WINS) {
            feeAmount = calculateFeeRecipientAmount(amount);
            feeRecipientData.feeRecipient.transferToken(transaction.token, feeAmount);
            emit FeeRecipientPayment(_transactionID, address(transaction.token), feeAmount);

            receiver.sendToken(transaction.token, amount - feeAmount);
            receiver.sendTo(receiverArbitrationFee);
        } else {
            uint256 splitArbitration = senderArbitrationFee / 2;
            uint256 splitAmount = amount / 2;

            feeAmount = calculateFeeRecipientAmount(splitAmount);
            feeRecipientData.feeRecipient.transferToken(transaction.token, feeAmount);
            emit FeeRecipientPayment(_transactionID, address(transaction.token), feeAmount);

            // In the case of an uneven token amount, one basic token unit can be burnt.
            sender.sendToken(transaction.token, splitAmount);
            receiver.sendToken(transaction.token, splitAmount - feeAmount);

            sender.sendTo(splitArbitration);
            receiver.sendTo(splitArbitration);
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
     * @return Amount to be paid.
     */
    function arbitrationCost() external view returns (uint256) {
        return arbitratorData.arbitrator.arbitrationCost(arbitratorExtraData);
    }
}
