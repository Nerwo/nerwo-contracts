// SPDX-License-Identifier: MIT
/**
 *  @title NerwoEscrow
 *  @author: [@eburgos, @n1c01a5, @sherpya]
 *
 *  @notice This contract implements an escrow system with dispute resolution, allowing secure transactions
 * between a client and a freelance. The contract holds funds on behalf of the client until the transaction
 * is completed or a dispute arises. If a dispute occurs, an external arbitrator determines the outcome.
 *
 * The main features of the contract are:
 * 1. Create transactions: The client initializes a transaction by providing details such as the freelance's
 *    address, the transaction amount, and any associated fees.
 * 2. Make payments: The client can pay the freelance if the goods or services are provided as expected.
 * 3. Reimbursements: The freelance can reimburse the client if the goods or services cannot be fully provided.
 * 4. Execute transactions: If the timeout has passed, the freelance can execute the transaction and receive
 *    the transaction amount.
 * 5. Timeouts: Both the client and freelance can trigger a timeout if the counterparty fails to pay the arbitration fee.
 * 6. Raise disputes and handle arbitration fees: Both parties can raise disputes and pay arbitration fees. The
 *    contract ensures that both parties pay the fees before raising a dispute.
 * 7. Submit evidence: Both parties can submit evidence to support their case during a dispute.
 * 8. Arbitrator ruling: The external arbitrator can provide a ruling to resolve the dispute. The ruling is
 *    executed by the contract, which redistributes the funds accordingly.
 */

pragma solidity ^0.8.20;

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
    error InvalidCaller();
    error InvalidStatus();
    error InvalidAmount();
    error InvalidTransaction();
    error InvalidToken();
    error InvalidFeeBasisPoint();
    error NotRuled();

    // **************************** //
    // *    Contract variables    * //
    // **************************** //
    uint8 private constant AMOUNT_OF_CHOICES = 2;
    uint8 private constant CLIENT_WINS = 1;
    uint8 private constant FREELANCE_WINS = 2;
    uint256 private constant MULTIPLIER_DIVISOR = 10000; // Divisor parameter for multipliers.

    enum Status {
        NoDispute,
        WaitingClient,
        WaitingFreelance,
        DisputeCreated,
        Resolved
    }

    struct Transaction {
        Status status;
        uint32 lastInteraction; // Last interaction for the dispute procedure.
        address client;
        address freelance;
        IERC20 token;
        uint256 amount;
        uint256 disputeID; // If dispute exists, the ID of the dispute.
        uint256 clientFee; // Total fees paid by the client.
        uint256 freelanceFee; // Total fees paid by the freelance.
    }

    uint256 public lastTransaction;

    IERC20[] private _tokensWhitelist; // whitelisted ERC20 tokens

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

    mapping(uint256 => Transaction) private _transactions;

    bytes public arbitratorExtraData; // Extra data to set up the arbitration.
    string public metaEvidenceURI;

    // **************************** //
    // *          Events          * //
    // **************************** //

    /** @dev To be emitted when a party pays or reimburses the other.
     *  @param transactionID The index of the transaction.
     *  @param token The token address.
     *  @param amount The amount paid.
     *  @param party The party that paid.
     */
    event Payment(uint256 indexed transactionID, IERC20 indexed token, uint256 amount, address indexed party);

    /** @dev Indicate that a party has to pay a fee or would otherwise be considered as losing.
     *  @param transactionID The index of the transaction.
     *  @param party The party who has to pay.
     */
    event HasToPayFee(uint256 indexed transactionID, address party);

    /** @dev Emitted when a transaction is created.
     *  @param transactionID The index of the transaction.
     *  @param client The address of the client.
     *  @param freelance The address of the freelance.
     *  @param token The token address
     *  @param amount The initial amount in the transaction.
     */
    event TransactionCreated(
        uint256 transactionID,
        address indexed client,
        address indexed freelance,
        IERC20 indexed token,
        uint256 amount
    );

    /** @dev To be emitted when a fee is received by the feeRecipient.
     *  @param transactionID The index of the transaction.
     *  @param token The Token Address.
     *  @param amount The amount paid.
     */
    event FeeRecipientPayment(uint256 indexed transactionID, IERC20 indexed token, uint256 amount);

    /** @dev To be emitted when a feeRecipient is changed.
     *  @param oldFeeRecipient Previous feeRecipient.
     *  @param newFeeRecipient Current feeRecipient.
     */
    event FeeRecipientChanged(address indexed oldFeeRecipient, address indexed newFeeRecipient);

    function _requireValidTransaction(uint256 transactionID) internal view {
        if (_transactions[transactionID].freelance == address(0)) {
            revert InvalidTransaction();
        }
    }

    modifier onlyValidTransaction(uint256 transactionID) {
        _requireValidTransaction(transactionID);
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
     *  @param owner_ The initial owner
     *  @param arbitrator The arbitrator of the contract.
     *  @param arbitratorProxy The arbitrator proxy of the contract.
     *  @param arbitratorExtraData_ Extra data for the arbitrator.
     *  @param feeTimeout Arbitration fee timeout for the parties.
     *  @param feeRecipient Address which receives a share of receiver payment.
     *  @param feeRecipientBasisPoint The share of fee to be received by the feeRecipient,
     *                                 down to 2 decimal places as 550 = 5.5%
     *  @param tokensWhitelist List of whitelisted ERC20 tokens
     */
    function initialize(
        address owner_,
        address arbitrator,
        address arbitratorProxy,
        bytes calldata arbitratorExtraData_,
        uint256 feeTimeout,
        address feeRecipient,
        uint256 feeRecipientBasisPoint,
        IERC20[] calldata tokensWhitelist
    ) external onlyOwner initializer {
        if (owner() != owner_) {
            _transferOwnership(owner_);
        }
        _setArbitratorData(arbitrator, arbitratorProxy, arbitratorExtraData_, feeTimeout);
        _setFeeRecipientAndBasisPoint(feeRecipient, feeRecipientBasisPoint);
        _setTokensWhitelist(tokensWhitelist);
    }

    // **************************** //
    // *        Setters           * //
    // **************************** //

    /**
     *  @dev modifies Arbitrator - Internal function without access restriction
     *  @param arbitrator The arbitrator of the contract.
     *  @param arbitratorProxy The arbitrator proxy of the contract.
     *  @param arbitratorExtraData_ Extra data for the arbitrator.
     *  @param feeTimeout Arbitration fee timeout for the parties.
     */
    function _setArbitratorData(
        address arbitrator,
        address arbitratorProxy,
        bytes calldata arbitratorExtraData_,
        uint256 feeTimeout
    ) internal {
        arbitratorData.arbitrator = IArbitrator(arbitrator);
        arbitratorData.proxy = IArbitrableProxy(arbitratorProxy);
        arbitratorExtraData = arbitratorExtraData_;
        arbitratorData.feeTimeout = uint32(feeTimeout);
    }

    /**
     *  @dev modifies Arbitrator Data - External function onlyOwner
     *  @param arbitrator The arbitrator of the contract.
     *  @param arbitratorProxy The arbitrator proxy of the contract.
     *  @param arbitratorExtraData_ Extra data for the arbitrator.
     *  @param feeTimeout Arbitration fee timeout for the parties.
     */
    function setArbitratorData(
        address arbitrator,
        address arbitratorProxy,
        bytes calldata arbitratorExtraData_,
        uint256 feeTimeout
    ) external onlyOwner {
        _setArbitratorData(arbitrator, arbitratorProxy, arbitratorExtraData_, feeTimeout);
    }

    /**
     *  @dev modifies fee recipient and basis point - Internal function without access restriction
     *  @param feeRecipient Address which receives a share of receiver payment.
     *  @param feeRecipientBasisPoint The share of fee to be received by the feeRecipient,
     *         down to 2 decimal places as 550 = 5.5%
     */
    function _setFeeRecipientAndBasisPoint(address feeRecipient, uint256 feeRecipientBasisPoint) internal {
        uint16 feeRecipientBasisPoint_ = uint16(feeRecipientBasisPoint);
        if (feeRecipientBasisPoint_ > MULTIPLIER_DIVISOR) {
            revert InvalidFeeBasisPoint();
        }

        feeRecipientData.feeRecipient = payable(feeRecipient);
        feeRecipientData.feeRecipientBasisPoint = feeRecipientBasisPoint_;
    }

    /**
     * @dev set platform metaEvedence IPFS URI
     * @param metaEvidenceURI_ The URI pointing to metaEvidence.json
     */
    function setMetaEvidenceURI(string calldata metaEvidenceURI_) external onlyOwner {
        _setMetaEvidenceURI(metaEvidenceURI_);
    }

    function _setMetaEvidenceURI(string calldata metaEvidenceURI_) internal {
        metaEvidenceURI = metaEvidenceURI_;
    }

    /**
     *  @dev modifies fee recipient and basis point - External function onlyOwner
     *  @param feeRecipient Address which receives a share of receiver payment.
     *  @param feeRecipientBasisPoint The share of fee to be received by the feeRecipient,
     *         down to 2 decimal places as 550 = 5.5%
     */
    function setFeeRecipientAndBasisPoint(address feeRecipient, uint256 feeRecipientBasisPoint) external onlyOwner {
        _setFeeRecipientAndBasisPoint(feeRecipient, feeRecipientBasisPoint);
    }

    function setTokensWhitelist(IERC20[] calldata tokensWhitelist) external onlyOwner {
        _setTokensWhitelist(tokensWhitelist);
    }

    /**
     * @dev Sets the whitelist of ERC20 tokens
     * @param tokensWhitelist An array of ERC20 tokens
     */
    function _setTokensWhitelist(IERC20[] calldata tokensWhitelist) internal {
        unchecked {
            delete _tokensWhitelist;
            for (uint i = 0; i < tokensWhitelist.length; i++) {
                _tokensWhitelist.push(tokensWhitelist[i]);
            }
        }
    }

    /** @dev Change Fee Recipient.
     *  @param newFeeRecipient Address of the new Fee Recipient.
     */
    function changeFeeRecipient(address newFeeRecipient) external {
        if (_msgSender() != feeRecipientData.feeRecipient) {
            revert InvalidCaller();
        }

        if (newFeeRecipient == address(0)) {
            revert NullAddress();
        }

        feeRecipientData.feeRecipient = newFeeRecipient;
        emit FeeRecipientChanged(_msgSender(), newFeeRecipient);
    }

    /** @dev Calculate the amount to be paid in wei according to feeRecipientBasisPoint for a particular amount.
     *  @param amount Amount to pay in wei.
     */
    function calculateFeeRecipientAmount(uint256 amount) public view returns (uint256) {
        return (amount * feeRecipientData.feeRecipientBasisPoint) / MULTIPLIER_DIVISOR;
    }

    /** @dev Create a transaction.
     *  @param token The ERC20 token contract.
     *  @param amount The amount of tokens in this transaction.
     *  @param freelance The recipient of the transaction.
     *  @return transactionID The index of the transaction.
     */
    function createTransaction(
        IERC20 token,
        uint256 amount,
        address freelance
    ) external returns (uint256 transactionID) {
        if (freelance == address(0)) {
            revert NullAddress();
        }

        if (amount == 0) {
            revert InvalidAmount();
        }

        // Amount too low to pay fee
        // WTF: solidity, nested if consumes less gas
        if (feeRecipientData.feeRecipientBasisPoint > 0) {
            if ((amount * feeRecipientData.feeRecipientBasisPoint) < MULTIPLIER_DIVISOR) {
                revert InvalidAmount();
            }
        }

        address client = _msgSender();
        if (client == freelance) {
            revert InvalidCaller();
        }

        IERC20 token_;
        unchecked {
            for (uint i = 0; i < _tokensWhitelist.length; i++) {
                if (token == _tokensWhitelist[i]) {
                    token_ = token;
                    break;
                }
            }
        }

        if (address(token_) == address(0)) {
            revert InvalidToken();
        }

        // first transfer tokens to the contract
        // NOTE: user must have approved the allowance
        if (!token_.transferFrom(client, address(this), amount)) {
            revert InvalidAmount();
        }

        unchecked {
            transactionID = ++lastTransaction;
        }

        _transactions[transactionID] = Transaction({
            status: Status.NoDispute,
            lastInteraction: uint32(block.timestamp),
            client: client,
            freelance: freelance,
            token: token_,
            amount: amount,
            disputeID: 0,
            clientFee: 0,
            freelanceFee: 0
        });

        emit TransactionCreated(transactionID, client, freelance, token, amount);
    }

    /** @dev Pay receiver. To be called if the good or service is provided.
     *  @param transactionID The index of the transaction.
     *  @param amount Amount to pay in wei.
     */
    function pay(uint256 transactionID, uint256 amount) external onlyValidTransaction(transactionID) {
        Transaction storage transaction = _transactions[transactionID];

        if (_msgSender() != transaction.client) {
            revert InvalidCaller();
        }

        if (transaction.status != Status.NoDispute) {
            revert InvalidStatus();
        }

        if ((amount == 0) || (transaction.amount == 0) || (amount > transaction.amount)) {
            revert InvalidAmount();
        }

        // _amount <= transaction.amount
        unchecked {
            transaction.amount -= amount;
        }

        uint256 feeAmount = calculateFeeRecipientAmount(amount);
        feeRecipientData.feeRecipient.transferToken(transaction.token, feeAmount);
        emit FeeRecipientPayment(transactionID, transaction.token, feeAmount);

        transaction.freelance.sendToken(transaction.token, amount - feeAmount);
        emit Payment(transactionID, transaction.token, amount, _msgSender());
    }

    /** @dev Reimburse sender. To be called if the good or service can't be fully provided.
     *  @param transactionID The index of the transaction.
     *  @param amountReimbursed Amount to reimburse in wei.
     */
    function reimburse(uint256 transactionID, uint256 amountReimbursed) external onlyValidTransaction(transactionID) {
        Transaction storage transaction = _transactions[transactionID];

        if (_msgSender() != transaction.freelance) {
            revert InvalidCaller();
        }

        if (transaction.status != Status.NoDispute) {
            revert InvalidStatus();
        }

        if ((amountReimbursed == 0) || (transaction.amount == 0) || (amountReimbursed > transaction.amount)) {
            revert InvalidAmount();
        }

        // _amountReimbursed <= transaction.amount
        unchecked {
            transaction.amount -= amountReimbursed;
        }

        transaction.client.sendToken(transaction.token, amountReimbursed);
        emit Payment(transactionID, transaction.token, amountReimbursed, _msgSender());
    }

    /** @dev Pay the arbitration fee to raise a dispute. To be called by the client or freelance. UNTRUSTED.
     *  Note that the arbitrator can have createDispute throw,
     *  which will make this function throw and therefore lead to a party being timed-out.
     *  @param transactionID The index of the transaction.
     */
    function payArbitrationFee(uint256 transactionID) external payable onlyValidTransaction(transactionID) {
        Transaction storage transaction = _transactions[transactionID];

        if (transaction.status >= Status.DisputeCreated) {
            revert InvalidStatus();
        }

        address sender = _msgSender();

        if ((sender != transaction.client) && (sender != transaction.freelance)) {
            revert InvalidCaller();
        }

        uint256 arbitrationCost_ = arbitratorData.arbitrator.arbitrationCost(arbitratorExtraData);

        if (msg.value != arbitrationCost_) {
            revert InvalidAmount();
        }

        transaction.lastInteraction = uint32(block.timestamp);

        if (sender == transaction.client) {
            transaction.clientFee = msg.value;
        } else {
            transaction.freelanceFee = msg.value;
        }

        // The other party. This can also happen if he has paid,
        // but arbitrationCost has increased.
        if (
            ((sender == transaction.client) && (transaction.freelanceFee != 0)) ||
            ((sender == transaction.freelance) && (transaction.clientFee != 0))
        ) {
            transaction.status = Status.DisputeCreated;
            transaction.disputeID = arbitratorData.proxy.createDispute{value: arbitrationCost_}(
                arbitratorExtraData,
                metaEvidenceURI,
                AMOUNT_OF_CHOICES
            );
        } else {
            address other = sender == transaction.client ? transaction.freelance : transaction.client;
            transaction.status = sender == transaction.client ? Status.WaitingFreelance : Status.WaitingClient;
            emit HasToPayFee(transactionID, other);
        }
    }

    /** @dev Reimburse a party if the other party fails to pay the fee.
     *  @param transactionID The index of the transaction.
     */
    function timeOut(uint256 transactionID) external onlyValidTransaction(transactionID) {
        Transaction storage transaction = _transactions[transactionID];

        if (block.timestamp - transaction.lastInteraction < arbitratorData.feeTimeout) {
            revert NoTimeout();
        }

        address sender = _msgSender();

        if (
            ((sender == transaction.client) && (transaction.status == Status.WaitingFreelance)) ||
            ((sender == transaction.freelance) && (transaction.status == Status.WaitingClient))
        ) {
            _executeRuling(transactionID, sender == transaction.client ? CLIENT_WINS : FREELANCE_WINS);
        } else {
            revert InvalidStatus();
        }
    }

    /** @dev Create a dispute. UNTRUSTED.
     *  @param transactionID The index of the transaction.
     *  @param arbitrationCost Amount to pay the arbitrator.
     */
    function _raiseDispute(uint256 transactionID, uint256 arbitrationCost) internal {
        Transaction storage transaction = _transactions[transactionID];
        transaction.status = Status.DisputeCreated;

        transaction.disputeID = arbitratorData.proxy.createDispute{value: arbitrationCost}(
            arbitratorExtraData,
            metaEvidenceURI,
            AMOUNT_OF_CHOICES
        );
    }

    /** @dev Accept ruling for a dispute.
     *  @param transactionID the transaction the dispute was created from.
     */
    function acceptRuling(uint256 transactionID) external onlyValidTransaction(transactionID) {
        Transaction storage transaction = _transactions[transactionID];

        if (transaction.status != Status.DisputeCreated) {
            revert InvalidStatus();
        }

        (, bool isRuled, uint256 ruling, ) = arbitratorData.proxy.disputes(transaction.disputeID);

        if (!isRuled) {
            revert NotRuled();
        }

        _executeRuling(transactionID, ruling);
    }

    /** @dev Execute a ruling of a dispute. It reimburses the fee to the winning party.
     *  @param transactionID The index of the transaction.
     *  @param ruling Ruling given by the arbitrator. 1 : Reimburse the receiver. 2 : Pay the sender.
     */
    function _executeRuling(uint256 transactionID, uint256 ruling) internal nonReentrant {
        Transaction storage transaction = _transactions[transactionID];

        uint256 amount = transaction.amount;
        uint256 clientArbitrationFee = transaction.clientFee;
        uint256 freelanceArbitrationFee = transaction.freelanceFee;

        transaction.amount = 0;
        transaction.clientFee = 0;
        transaction.freelanceFee = 0;
        transaction.status = Status.Resolved;

        uint256 feeAmount;
        address client = transaction.client;
        address freelance = transaction.freelance;

        // Give the arbitration fee back.
        // Note that we use send to prevent a party from blocking the execution.
        if (ruling == CLIENT_WINS) {
            client.sendToken(transaction.token, amount);
            client.sendTo(clientArbitrationFee);
        } else if (ruling == FREELANCE_WINS) {
            feeAmount = calculateFeeRecipientAmount(amount);
            feeRecipientData.feeRecipient.transferToken(transaction.token, feeAmount);
            emit FeeRecipientPayment(transactionID, transaction.token, feeAmount);

            freelance.sendToken(transaction.token, amount - feeAmount);
            freelance.sendTo(freelanceArbitrationFee);
        } else {
            uint256 splitArbitration = clientArbitrationFee / 2;
            uint256 splitAmount = amount / 2;

            feeAmount = calculateFeeRecipientAmount(splitAmount);
            feeRecipientData.feeRecipient.transferToken(transaction.token, feeAmount);
            emit FeeRecipientPayment(transactionID, transaction.token, feeAmount);

            // In the case of an uneven token amount, one basic token unit can be burnt.
            client.sendToken(transaction.token, splitAmount);
            freelance.sendToken(transaction.token, splitAmount - feeAmount);

            client.sendTo(splitArbitration);
            freelance.sendTo(splitArbitration);
        }
    }

    // **************************** //
    // *   Utils for frontends    * //
    // **************************** //

    /**
     * @dev Get transaction by id
     *  @param transactionID The index of the transaction.
     * @return transaction
     */
    function getTransaction(
        uint256 transactionID
    ) external view onlyValidTransaction(transactionID) returns (Transaction memory) {
        return _transactions[transactionID];
    }

    /**
     * @dev Get supported ERC20 tokens
     * @return tokens array of addresses of supported tokens
     */
    function getSupportedTokens() external view returns (IERC20[] memory) {
        return _tokensWhitelist;
    }

    /**
     * @dev Ask arbitrator for abitration cost
     * @return Amount to be paid.
     */
    function getArbitrationCost() external view returns (uint256) {
        return arbitratorData.arbitrator.arbitrationCost(arbitratorExtraData);
    }

    /** @dev Get ruling for the disupte of given transaction
     *  @param transactionID the transaction the dispute was created from.
     */
    function fetchRuling(
        uint256 transactionID
    ) external view onlyValidTransaction(transactionID) returns (bool isRuled, uint256 ruling) {
        Transaction storage transaction = _transactions[transactionID];

        if (transaction.status != Status.DisputeCreated) {
            revert InvalidStatus();
        }

        (, isRuled, ruling, ) = arbitratorData.proxy.disputes(transaction.disputeID);
    }
}
