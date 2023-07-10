// SPDX-License-Identifier: MIT
/**
 *  @title NerwoEscrow
 *  @author Gianluigi Tiesi <sherpya@gmail.com>
 *  @notice Original authors of the Kleros escrow example: @eburgos, @n1c01a5
 *
 *  @notice This contract implements an escrow system with dispute resolution, allowing secure transactions
 * between a client and a freelancer. The contract holds funds on behalf of the client until the transaction
 * is completed or a dispute arises. If a dispute occurs, an external arbitrator determines the outcome.
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
    uint8 private constant FREELANCER_WINS = 2;
    uint256 private constant MULTIPLIER_DIVISOR = 10_000; // Divisor parameter for multipliers.

    enum Status {
        NoDispute,
        WaitingClient,
        WaitingFreelancer,
        DisputeCreated,
        Resolved
    }

    struct Transaction {
        Status status;
        uint32 lastInteraction; // Last interaction for the dispute procedure.
        address client;
        address freelancer;
        IERC20 token;
        uint256 amount;
        uint256 disputeID; // If dispute exists, the ID of the dispute.
        uint256 clientFee; // Total fees paid by the client.
        uint256 freelancerFee; // Total fees paid by the freelancer.
    }

    uint256 public lastTransaction;

    struct TokenAllow {
        IERC20 token;
        bool allow;
    }

    mapping(IERC20 => bool) tokens; // whitelisted ERC20 tokens

    struct ArbitratorData {
        uint32 feeTimeout; // Time in seconds a party can take to pay arbitration
        // fees before being considered unresponding and lose the dispute.
        IArbitrator arbitrator; // Address of the arbitrator contract.
        IArbitrableProxy proxy; // Address of the arbitrator proxy contract.
        string metaEvidenceURI; // metaEvidence uri to set up the arbitration.
        bytes extraData; // Extra data to set up the arbitration.
    }

    ArbitratorData public arbitratorData;

    struct FeeRecipientData {
        address feeRecipient; // Address which receives a share of receiver payment.
        uint16 feeRecipientBasisPoint; // The share of fee to be received by the feeRecipient, in basis points. Note that this value shouldn't exceed Divisor.
    }

    FeeRecipientData public feeRecipientData;

    mapping(uint256 => Transaction) private _transactions;

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

    /**
     * @dev To be emitted when a dispute is created.
     * @param transactionID of the dispute.
     * @param disputeID ID of the dispute.
     * @param plaintiff The address started the dispute creation.
     */
    event DisputeCreated(uint256 indexed transactionID, uint256 indexed disputeID, address indexed plaintiff);

    /** @dev Emitted when a transaction is created.
     *  @param transactionID The index of the transaction.
     *  @param client The address of the client.
     *  @param freelancer The address of the freelancer.
     *  @param token The token address
     *  @param amount The initial amount in the transaction.
     */
    event TransactionCreated(
        uint256 transactionID,
        address indexed client,
        address indexed freelancer,
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

    /** @dev To be emitted when the whitelist was changed.
     *  @param token The token that was either added or removed from whitelist.
     *  @param allow Whether added or removed.
     */
    event WhitelistChanged(IERC20 token, bool allow);

    function _requireValidTransaction(uint256 transactionID) internal view {
        if (_transactions[transactionID].freelancer == address(0)) {
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
     *  @param newOwner The initial owner
     *  @param feeTimeout Arbitration fee timeout for the parties.
     *  @param arbitrator The arbitrator of the contract.
     *  @param arbitratorProxy The arbitrator proxy of the contract.
     *  @param arbitratorExtraData Extra data for the arbitrator.
     *  @param metaEvidenceURI Meta Evidence json IPFS URI
     *  @param feeRecipient Address which receives a share of receiver payment.
     *  @param feeRecipientBasisPoint The share of fee to be received by the feeRecipient,
     *                                 down to 2 decimal places as 550 = 5.5%
     *  @param supportedTokens List of whitelisted ERC20 tokens
     */
    function initialize(
        address newOwner,
        uint256 feeTimeout,
        address arbitrator,
        address arbitratorProxy,
        bytes calldata arbitratorExtraData,
        string calldata metaEvidenceURI,
        address feeRecipient,
        uint256 feeRecipientBasisPoint,
        TokenAllow[] calldata supportedTokens
    ) external onlyOwner initializer {
        if (owner() != newOwner) {
            _transferOwnership(newOwner);
        }
        _setArbitratorData(feeTimeout, arbitrator, arbitratorProxy, arbitratorExtraData);
        _setFeeRecipientAndBasisPoint(feeRecipient, feeRecipientBasisPoint);
        _setMetaEvidenceURI(metaEvidenceURI);
        _changeWhiteList(supportedTokens);
    }

    // **************************** //
    // *        Setters           * //
    // **************************** //

    /**
     *  @dev modifies Arbitrator - Internal function without access restriction
     *  @param feeTimeout Arbitration fee timeout for the parties.
     *  @param arbitrator The arbitrator of the contract.
     *  @param arbitratorProxy The arbitrator proxy of the contract.
     *  @param arbitratorExtraData Extra data for the arbitrator.
     */
    function _setArbitratorData(
        uint256 feeTimeout,
        address arbitrator,
        address arbitratorProxy,
        bytes calldata arbitratorExtraData
    ) internal {
        arbitratorData.feeTimeout = uint32(feeTimeout);
        arbitratorData.arbitrator = IArbitrator(arbitrator);
        arbitratorData.proxy = IArbitrableProxy(arbitratorProxy);
        arbitratorData.extraData = arbitratorExtraData;
    }

    /**
     *  @dev modifies Arbitrator Data - External function onlyOwner
     *  @param feeTimeout Arbitration fee timeout for the parties.
     *  @param arbitrator The arbitrator of the contract.
     *  @param arbitratorProxy The arbitrator proxy of the contract.
     *  @param arbitratorExtraData Extra data for the arbitrator.
     */
    function setArbitratorData(
        uint256 feeTimeout,
        address arbitrator,
        address arbitratorProxy,
        bytes calldata arbitratorExtraData
    ) external onlyOwner {
        _setArbitratorData(feeTimeout, arbitrator, arbitratorProxy, arbitratorExtraData);
    }

    /**
     *  @dev modifies fee reciarbitratorDatapient and basis point - Internal function without access restriction
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
        arbitratorData.metaEvidenceURI = metaEvidenceURI_;
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

    function changeWhitelist(TokenAllow[] calldata tokensWhitelist) external onlyOwner {
        _changeWhiteList(tokensWhitelist);
    }

    /**
     * @dev Sets whitelisted ERC20 tokens
     * @param supportedTokens An array of TokenAllow
     */
    function _changeWhiteList(TokenAllow[] calldata supportedTokens) internal {
        unchecked {
            for (uint i = 0; i < supportedTokens.length; i++) {
                tokens[supportedTokens[i].token] = supportedTokens[i].allow;
                emit WhitelistChanged(supportedTokens[i].token, supportedTokens[i].allow);
            }
        }
    }

    /** @dev Change Fee Recipient.
     *  @param newFeeRecipient Address of the new Fee Recipient.
     */
    function changeFeeRecipient(address newFeeRecipient) external onlyOwner {
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
     *  @param freelancer The recipient of the transaction.
     *  @return transactionID The index of the transaction.
     */
    function createTransaction(
        IERC20 token,
        uint256 amount,
        address freelancer
    ) external returns (uint256 transactionID) {
        if (freelancer == address(0)) {
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
        if (client == freelancer) {
            revert InvalidCaller();
        }

        if (!tokens[token]) {
            revert InvalidToken();
        }

        // first transfer tokens to the contract
        // NOTE: user must have approved the allowance
        if (!token.transferFrom(client, address(this), amount)) {
            revert InvalidAmount();
        }

        unchecked {
            transactionID = ++lastTransaction;
        }

        _transactions[transactionID] = Transaction({
            status: Status.NoDispute,
            lastInteraction: uint32(block.timestamp),
            client: client,
            freelancer: freelancer,
            token: token,
            amount: amount,
            disputeID: 0,
            clientFee: 0,
            freelancerFee: 0
        });

        emit TransactionCreated(transactionID, client, freelancer, token, amount);
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

        transaction.freelancer.sendToken(transaction.token, amount - feeAmount);
        emit Payment(transactionID, transaction.token, amount, _msgSender());
    }

    /** @dev Reimburse sender. To be called if the good or service can't be fully provided.
     *  @param transactionID The index of the transaction.
     *  @param amountReimbursed Amount to reimburse in wei.
     */
    function reimburse(uint256 transactionID, uint256 amountReimbursed) external onlyValidTransaction(transactionID) {
        Transaction storage transaction = _transactions[transactionID];

        if (_msgSender() != transaction.freelancer) {
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

    /** @dev Pay the arbitration fee to raise a dispute. To be called by the client or freelancer. UNTRUSTED.
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

        if ((sender != transaction.client) && (sender != transaction.freelancer)) {
            revert InvalidCaller();
        }

        uint256 arbitrationCost_ = arbitratorData.arbitrator.arbitrationCost(arbitratorData.extraData);

        if (msg.value != arbitrationCost_) {
            revert InvalidAmount();
        }

        transaction.lastInteraction = uint32(block.timestamp);

        if (sender == transaction.client) {
            transaction.clientFee = msg.value;
        } else {
            transaction.freelancerFee = msg.value;
        }

        address other = sender == transaction.client ? transaction.freelancer : transaction.client;

        if (
            ((sender == transaction.client) && (transaction.freelancerFee != 0)) ||
            ((sender == transaction.freelancer) && (transaction.clientFee != 0))
        ) {
            transaction.status = Status.DisputeCreated;
            transaction.disputeID = arbitratorData.proxy.createDispute{value: arbitrationCost_}(
                arbitratorData.extraData,
                arbitratorData.metaEvidenceURI,
                AMOUNT_OF_CHOICES
            );
            emit DisputeCreated(transactionID, transaction.disputeID, other);
        } else {
            transaction.status = sender == transaction.client ? Status.WaitingFreelancer : Status.WaitingClient;
            emit HasToPayFee(transactionID, other);
        }
    }

    /** @dev A function to handle a scenario where a party fails to pay the fee within the defined time limit.
     *  It allows for a timeout period and then reimburses the other party.
     *  Only a valid transaction can call this function.
     *  @param transactionID The ID of the transaction where a party failed to pay the fee.
     */
    function timeOut(uint256 transactionID) external nonReentrant onlyValidTransaction(transactionID) {
        Transaction storage transaction = _transactions[transactionID];

        if (block.timestamp - transaction.lastInteraction < arbitratorData.feeTimeout) {
            revert NoTimeout();
        }

        address sender = _msgSender();

        if (
            ((sender == transaction.client) && (transaction.status == Status.WaitingFreelancer)) ||
            ((sender == transaction.freelancer) && (transaction.status == Status.WaitingClient))
        ) {
            _executeRuling(transactionID, sender == transaction.client ? CLIENT_WINS : FREELANCER_WINS);
        } else {
            revert InvalidStatus();
        }
    }

    /** @dev Accept ruling for a dispute.
     *  @param transactionID the transaction the dispute was created from.
     */
    function acceptRuling(uint256 transactionID) external nonReentrant onlyValidTransaction(transactionID) {
        Transaction storage transaction = _transactions[transactionID];

        if (transaction.status != Status.DisputeCreated) {
            revert InvalidStatus();
        }

        uint256 localID = arbitratorData.proxy.externalIDtoLocalID(transaction.disputeID);
        (, bool isRuled, uint256 ruling, ) = arbitratorData.proxy.disputes(localID);

        if (!isRuled) {
            revert NotRuled();
        }

        _executeRuling(transactionID, ruling);
    }

    /** @dev A function to execute the ruling provided by the arbitrator. It distributes the funds based on the ruling.
     *  The ruling is executed in a way that it prevents reentrancy attacks.
     *  After executing the ruling, the status of the transaction is set to Resolved.
     *  @param transactionID The ID of the transaction where a ruling needs to be executed.
     *  @param ruling The ruling provided by the arbitrator. 1 means the client wins, 2 means the freelancerr wins.
     */
    function _executeRuling(uint256 transactionID, uint256 ruling) internal {
        Transaction storage transaction = _transactions[transactionID];

        uint256 amount = transaction.amount;
        uint256 clientArbitrationFee = transaction.clientFee;
        uint256 freelancerArbitrationFee = transaction.freelancerFee;

        transaction.amount = 0;
        transaction.clientFee = 0;
        transaction.freelancerFee = 0;
        transaction.status = Status.Resolved;

        uint256 feeAmount;
        address client = transaction.client;
        address freelancer = transaction.freelancer;

        // Give the arbitration fee back.
        // Note that we use send to prevent a party from blocking the execution.
        if (ruling == CLIENT_WINS) {
            client.sendToken(transaction.token, amount);
            client.sendTo(clientArbitrationFee);
        } else if (ruling == FREELANCER_WINS) {
            feeAmount = calculateFeeRecipientAmount(amount);
            feeRecipientData.feeRecipient.transferToken(transaction.token, feeAmount);
            emit FeeRecipientPayment(transactionID, transaction.token, feeAmount);

            freelancer.sendToken(transaction.token, amount - feeAmount);
            freelancer.sendTo(freelancerArbitrationFee);
        } else {
            uint256 splitArbitration = clientArbitrationFee / 2;
            uint256 splitAmount = amount / 2;

            feeAmount = calculateFeeRecipientAmount(splitAmount);
            feeRecipientData.feeRecipient.transferToken(transaction.token, feeAmount);
            emit FeeRecipientPayment(transactionID, transaction.token, feeAmount);

            // In the case of an uneven token amount, one basic token unit can be burnt.
            client.sendToken(transaction.token, splitAmount);
            freelancer.sendToken(transaction.token, splitAmount - feeAmount);

            client.sendTo(splitArbitration);
            freelancer.sendTo(splitArbitration);
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
     * @dev Ask arbitrator for abitration cost
     * @return Amount to be paid.
     */
    function getArbitrationCost() external view returns (uint256) {
        return arbitratorData.arbitrator.arbitrationCost(arbitratorData.extraData);
    }

    /** @dev Get the ruling for the dispute of given transaction
     *  @param transactionID the transaction the dispute was created from.
     */
    function fetchRuling(
        uint256 transactionID
    ) external view onlyValidTransaction(transactionID) returns (bool isRuled, uint256 ruling) {
        Transaction storage transaction = _transactions[transactionID];

        if (transaction.status < Status.DisputeCreated) {
            revert InvalidStatus();
        }

        uint256 localID = arbitratorData.proxy.externalIDtoLocalID(transaction.disputeID);
        (, isRuled, ruling, ) = arbitratorData.proxy.disputes(localID);
    }
}
