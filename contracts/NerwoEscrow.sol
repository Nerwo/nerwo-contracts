// SPDX-License-Identifier: MIT
/**
 *  @title NerwoEscrow
 *  @author Gianluigi Tiesi <sherpya@gmail.com>
 *  @notice Original authors of the Kleros escrow example: @eburgos, @n1c01a5
 *
 *                         ////////                 ////////
 *                       ////////////             ////////////
 *                       /////////////            ////////////
 *                       //////////////           ////////////
 *                         /////////////            ////////
 *                              ,/////////
 *                                    /////*
 *                                       /////
 *                                         //////
 *                                           /////////,
 *                         ////////            /////////////
 *                       ////////////           //////////////
 *                      ,////////////            /////////////
 *                       ////////////             ////////////
 *                         ////////                 ////////
 *
 *  @notice This contract implements an escrow system with dispute resolution, allowing secure transactions
 *  between a client and a freelancer. The contract holds funds on behalf of the client until the transaction
 *  is completed or a dispute arises. If a dispute occurs, an external arbitrator determines the outcome.
 */

pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IArbitrator} from "@kleros/erc-792/contracts/IArbitrator.sol";
import {IArbitrable} from "@kleros/erc-792/contracts/IArbitrable.sol";

import {SafeTransfer} from "./SafeTransfer.sol";

contract NerwoEscrow is Ownable, ReentrancyGuard, IArbitrable {
    using SafeTransfer for address;
    using SafeTransfer for IERC20;

    error NullAddress();
    error NoTimeout();
    error InvalidCaller();
    error InvalidStatus();
    error InvalidAmount();
    error TokenTransferFailed();
    error AlreadyPaid();
    error InvalidTransaction();
    error InvalidToken();
    error InvalidFeeBasisPoint();
    error OfferAlreadyFunded();

    // **************************** //
    // *    Contract variables    * //
    // **************************** //
    uint256 private constant AMOUNT_OF_CHOICES = 2;
    uint256 private constant CLIENT_WINS = 1;
    uint256 private constant FREELANCER_WINS = 2;
    uint256 private constant MAX_FEEBASISPOINT = 2_000; // 20%
    uint256 private constant MULTIPLIER_DIVISOR = 10_000; // Divisor parameter for multipliers.
    uint256 private constant MIN_AMOUNT = 10_000; // Minimal amount with non zero fee basis point for non zero fee
    uint256 public constant CAP_UNLIMITED = type(uint256).max;

    enum Status {
        NoDispute,
        WaitingClient,
        WaitingFreelancer,
        DisputeCreated,
        Resolved
    }

    struct Transaction {
        Status status;
        uint8 ruling;
        uint32 lastInteraction; // Last interaction for the dispute procedure.
        address client;
        address freelancer;
        address feeRecipient;
        IERC20 token;
        uint16 feeRecipientBasisPoint;
        uint256 amount;
        uint256 disputeID; // If dispute exists, the ID of the dispute.
        uint256 clientFee; // Total fees paid by the client.
        uint256 freelancerFee; // Total fees paid by the freelancer.
        uint256 arbitrationCost; // Frozen at the first payArbitrationFee call.
    }

    uint256 public lastTransaction;

    /// @notice Maximum amount accepted per transaction for each token.
    /// @dev A cap of 0 disables the token. CAP_UNLIMITED allows any amount.
    mapping(IERC20 => uint256) public amountCaps;

    struct ArbitratorData {
        // Time in seconds a party can take to pay arbitration
        // fees before being considered unresponding and lose the dispute.
        uint32 feeTimeout;
        IArbitrator arbitrator; // Address of the arbitrator contract.
        string metaEvidenceURI; // metaEvidence uri to set up the arbitration.
        bytes extraData; // Extra data to set up the arbitration.
    }

    ArbitratorData public arbitratorData;

    struct FeeRecipientData {
        address feeRecipient; // Address which receives a share of receiver payment.
        // The share of fee to be received by the feeRecipient,
        // in basis points. Note that this value shouldn't exceed Divisor.
        uint16 feeRecipientBasisPoint;
    }

    FeeRecipientData public feeRecipientData;

    mapping(uint256 => Transaction) private _transactions;
    mapping(bytes16 => uint256) public transactionIdByOfferId;
    mapping(uint256 => uint256) public transactionIdByDisputeId;
    mapping(IERC20 => mapping(address => uint256)) public pendingWithdrawals;

    // **************************** //
    // *          Events          * //
    // **************************** //

    /**
     * @dev To be emitted when the client pays the freelancer.
     *  @param transactionID The index of the transaction.
     *  @param from The address that paid.
     *  @param to The address that received the payment.
     *  @param token The token address.
     *  @param amount The amount paid.
     */
    event Payment(
        uint256 indexed transactionID, address indexed from, address indexed to, IERC20 token, uint256 amount
    );

    /**
     * @dev To be emitted when the freelancer reimburses the client.
     *  @param transactionID The index of the transaction.
     *  @param from The address that paid.
     *  @param to The address that received the payment.
     *  @param token The token address.
     *  @param amount The amount paid.
     */
    event Reimburse(
        uint256 indexed transactionID, address indexed from, address indexed to, IERC20 token, uint256 amount
    );

    /**
     * @dev Indicate that a party has to pay a fee or would otherwise be considered as losing.
     *  @param transactionID The index of the transaction.
     *  @param party The party who has to pay.
     */
    event HasToPayFee(uint256 indexed transactionID, address indexed party);

    /**
     * @dev To be emitted when a dispute is created.
     * @param transactionID of the dispute.
     * @param disputeID ID of the dispute.
     * @param plaintiff The address started the dispute creation.
     */
    event DisputeCreated(uint256 indexed transactionID, uint256 indexed disputeID, address indexed plaintiff);

    /**
     * @dev Emitted when a dispute fee timeout is executed.
     * @param transactionID The transaction resolved by timeout.
     * @param winner The party who won by timeout.
     * @param ruling The ruling executed by timeout.
     */
    event TimeoutExecuted(uint256 indexed transactionID, address indexed winner, uint256 ruling);

    /**
     * @dev Emitted when an arbitrator ruling is accepted and executed.
     * @param transactionID The transaction resolved by ruling.
     * @param disputeID The arbitrator dispute id.
     * @param ruling The accepted ruling.
     */
    event RulingAccepted(uint256 indexed transactionID, uint256 indexed disputeID, uint256 ruling);

    /**
     * @dev Emitted when a transaction is created.
     *  @param offerID The UUIDv7 offer id this transaction funds.
     *  @param transactionID The index of the transaction.
     *  @param client The address of the client.
     *  @param freelancer The address of the freelancer.
     *  @param token The token address
     *  @param amount The initial amount in the transaction.
     */
    event TransactionCreated(
        bytes16 indexed offerID,
        uint256 indexed transactionID,
        address indexed client,
        address freelancer,
        IERC20 token,
        uint256 amount
    );

    /**
     * @dev To be emitted when a fee is received by the feeRecipient.
     *  @param transactionID The index of the transaction.
     *  @param recipient The fee recipient.
     *  @param token The Token Address.
     *  @param amount The amount paid.
     */
    event FeeRecipientPayment(
        uint256 indexed transactionID, address indexed recipient, IERC20 indexed token, uint256 amount
    );

    /**
     * @dev To be emitted when a feeRecipient is changed.
     *  @param newFeeRecipient new fee Recipient.
     *  @param newBasisPoint new fee BasisPoint.
     */
    event FeeRecipientChanged(address indexed newFeeRecipient, uint256 newBasisPoint);

    /**
     * @dev Emitted when a token transaction amount cap is changed.
     *  @param token Token whose cap changed. address(0) is the native token.
     *  @param cap New per-transaction cap. 0 disables the token; CAP_UNLIMITED removes the limit.
     */
    event TokenCapChanged(IERC20 indexed token, uint256 cap);

    /**
     * @dev To be emitted when the contract if funded with ether by admin.
     *  @param funder The address that funded.
     *  @param amount The amount funded.
     */
    event ContractFunded(address indexed funder, uint256 amount);

    event WithdrawalCredited(address indexed recipient, IERC20 indexed token, uint256 amount);
    event WithdrawalClaimed(address indexed recipient, IERC20 indexed token, uint256 amount);

    function _requireValidTransaction(uint256 transactionID) internal view {
        if (_transactions[transactionID].freelancer == address(0)) {
            revert InvalidTransaction();
        }
    }

    modifier onlyValidTransaction(uint256 transactionID) {
        _requireValidTransaction(transactionID);
        _;
    }

    /**
     * @dev Constructor. The native token is enabled without a per-transaction amount limit.
     *  @param newOwner The initial owner
     *  @param arbitrator arbitrator address.
     *  @param metaEvidenceURI Meta Evidence json IPFS URI
     *  @param feeRecipient Address which receives a share of receiver payment.
     *  @param feeRecipientBasisPoint The share of fee to be received by the feeRecipient, down to 2 decimal places as 550 = 5.5%
     */
    constructor(
        address newOwner,
        address arbitrator,
        string memory metaEvidenceURI,
        address feeRecipient,
        uint256 feeRecipientBasisPoint
    ) Ownable(msg.sender) {
        // cannot set newOwner here because it would break guarded calls
        setFeeRecipientAndBasisPoint(feeRecipient, feeRecipientBasisPoint);
        amountCaps[SafeTransfer.NATIVE_TOKEN] = CAP_UNLIMITED;
        emit TokenCapChanged(SafeTransfer.NATIVE_TOKEN, CAP_UNLIMITED);

        arbitratorData.feeTimeout = 604800;
        arbitratorData.arbitrator = IArbitrator(arbitrator);
        arbitratorData.extraData =
            hex"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003";
        arbitratorData.metaEvidenceURI = metaEvidenceURI;

        if (owner() != newOwner) {
            _transferOwnership(newOwner);
        }
    }

    // **************************** //
    // *        Setters           * //
    // **************************** //

    /**
     *  @dev modifies fee reciarbitratorDatapient and basis point
     *  @param newFeeRecipient Address which receives a share of receiver payment.
     *  @param feeRecipientBasisPoint The share of fee to be received by the feeRecipient, down to 2 decimal places as 550 = 5.5%
     */
    function setFeeRecipientAndBasisPoint(address newFeeRecipient, uint256 feeRecipientBasisPoint) public onlyOwner {
        if (newFeeRecipient == address(0)) {
            revert NullAddress();
        }

        if (feeRecipientBasisPoint > MAX_FEEBASISPOINT) {
            revert InvalidFeeBasisPoint();
        }

        // forge-lint: disable-next-line(unsafe-typecast)
        uint16 feeRecipientBasisPoint_ = uint16(feeRecipientBasisPoint);
        feeRecipientData.feeRecipient = payable(newFeeRecipient);
        feeRecipientData.feeRecipientBasisPoint = feeRecipientBasisPoint_;

        emit FeeRecipientChanged(newFeeRecipient, feeRecipientBasisPoint_);
    }

    function setMetaEvidenceURI(string calldata metaEvidenceURI_) external onlyOwner {
        arbitratorData.metaEvidenceURI = metaEvidenceURI_;
    }

    function setExtraData(bytes calldata arbitratorExtraData) external onlyOwner {
        arbitratorData.extraData = arbitratorExtraData;
    }

    /**
     * @dev Sets the maximum amount accepted per transaction for a token.
     * @notice Setting `amountCap` to 0 disables the token. Setting it to
     * `CAP_UNLIMITED` enables the token without an amount limit.
     * @param token Token whose cap is being changed. Use address(0) for native token.
     * @param amountCap New per-transaction cap in the token's smallest unit.
     */
    function changeTokenCap(IERC20 token, uint256 amountCap) external onlyOwner {
        if (address(token) != address(SafeTransfer.NATIVE_TOKEN)) {
            if (address(token).code.length == 0) {
                revert InvalidToken();
            }
            (bool success, bytes memory data) =
                address(token).staticcall(abi.encodeCall(IERC20.balanceOf, (address(this))));
            if (!success || data.length < 32) {
                revert InvalidToken();
            }
        }

        amountCaps[token] = amountCap;
        emit TokenCapChanged(token, amountCap);
    }

    /**
     * @dev Admin function to fund the contract with ether, e.g. to unblock if the arbitrator cost changes in between (possible?)
     *  @notice It's harmless and there is no withdraw function.
     */
    // solhint-disable-next-line no-complex-fallback
    receive() external payable {
        if (owner() != msg.sender) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
        emit ContractFunded(msg.sender, msg.value);
    }

    /**
     * @dev Calculate the amount to be paid in wei according to feeRecipientBasisPoint for a particular amount.
     *  @param amount Amount to pay in wei.
     */
    function calculateFeeRecipientAmount(uint256 amount) public view returns (uint256) {
        return _calculateFeeRecipientAmount(amount, feeRecipientData.feeRecipientBasisPoint);
    }

    function _calculateFeeRecipientAmount(uint256 amount, uint16 feeRecipientBasisPoint)
        internal
        pure
        returns (uint256)
    {
        return (amount * feeRecipientBasisPoint) / MULTIPLIER_DIVISOR;
    }

    /**
     * @dev Create a transaction.
     *  @param offerID The UUIDv7 offer id this transaction funds.
     *  @param token The ERC20 token contract.
     *  @param amount The amount of tokens in this transaction.
     *  @param freelancer The recipient of the transaction.
     *  @return transactionID The index of the transaction.
     */
    function createTransaction(bytes16 offerID, IERC20 token, uint256 amount, address freelancer)
        external
        payable
        nonReentrant
        returns (uint256 transactionID)
    {
        uint256 transactionAmount = amount;

        if (freelancer == address(0)) {
            revert NullAddress();
        }

        // Amount too low to pay fee
        if (amount < MIN_AMOUNT) {
            revert InvalidAmount();
        }

        if (msg.sender == freelancer) {
            revert InvalidCaller();
        }

        if (transactionIdByOfferId[offerID] != 0) {
            revert OfferAlreadyFunded();
        }

        uint256 cap = amountCaps[token];

        // Only tokens with a non-zero cap are accepted.
        if (cap == 0) {
            revert InvalidToken();
        }

        if (amount > cap) {
            revert InvalidAmount();
        }

        if (address(token) == address(SafeTransfer.NATIVE_TOKEN)) {
            // Native Token
            if (msg.value != amount) {
                revert InvalidAmount();
            }
        } else {
            // ERC20
            if (msg.value != 0) {
                revert InvalidToken();
            }
            // first transfer tokens to the contract
            // NOTE: user must have approved the allowance
            uint256 balanceBefore = token.balanceOf(address(this));
            if (!token.safeTransferFrom(msg.sender, address(this), amount)) {
                revert TokenTransferFailed();
            }
            transactionAmount = token.balanceOf(address(this)) - balanceBefore;
            if (transactionAmount < MIN_AMOUNT) {
                revert InvalidAmount();
            }
        }

        unchecked {
            transactionID = ++lastTransaction;
        }

        _transactions[transactionID] = Transaction({
            status: Status.NoDispute,
            ruling: 0,
            lastInteraction: uint32(block.timestamp),
            client: msg.sender,
            freelancer: freelancer,
            feeRecipient: feeRecipientData.feeRecipient,
            token: token,
            feeRecipientBasisPoint: feeRecipientData.feeRecipientBasisPoint,
            amount: transactionAmount,
            disputeID: 0,
            clientFee: 0,
            freelancerFee: 0,
            arbitrationCost: 0
        });
        transactionIdByOfferId[offerID] = transactionID;

        emit TransactionCreated(offerID, transactionID, msg.sender, freelancer, token, transactionAmount);
    }

    /**
     * @dev Pay receiver. To be called if the good or service is provided.
     *  @param transactionID The index of the transaction
     */
    function pay(uint256 transactionID) external nonReentrant onlyValidTransaction(transactionID) {
        Transaction storage transaction = _transactions[transactionID];

        if (msg.sender != transaction.client) {
            revert InvalidCaller();
        }

        if (transaction.status != Status.NoDispute) {
            revert InvalidStatus();
        }

        if (transaction.amount == 0) {
            revert InvalidAmount();
        }

        uint256 amount = transaction.amount;
        transaction.amount = 0;

        uint256 feeAmount = _calculateFeeRecipientAmount(amount, transaction.feeRecipientBasisPoint);
        if (feeAmount != 0) {
            _sendOrCredit(transaction.feeRecipient, transaction.token, feeAmount);
            emit FeeRecipientPayment(transactionID, transaction.feeRecipient, transaction.token, feeAmount);
        }

        _sendOrCredit(transaction.freelancer, transaction.token, amount - feeAmount);
        emit Payment(transactionID, msg.sender, transaction.freelancer, transaction.token, amount - feeAmount);
    }

    /**
     * @dev Reimburse sender. To be called if the good or service can't be fully provided.
     *  @param transactionID The index of the transaction.
     */
    function reimburse(uint256 transactionID) external nonReentrant onlyValidTransaction(transactionID) {
        Transaction storage transaction = _transactions[transactionID];

        if (msg.sender != transaction.freelancer) {
            revert InvalidCaller();
        }

        if (transaction.status != Status.NoDispute) {
            revert InvalidStatus();
        }

        if (transaction.amount == 0) {
            revert InvalidAmount();
        }

        uint256 amountReimbursed = transaction.amount;
        transaction.amount = 0;

        _sendOrCredit(transaction.client, transaction.token, amountReimbursed);
        emit Reimburse(transactionID, msg.sender, transaction.client, transaction.token, amountReimbursed);
    }

    /**
     * @dev Pay the arbitration fee to raise a dispute. To be called by the client or freelancer. UNTRUSTED.
     *  Note that the arbitrator can have createDispute throw,
     *  which will make this function throw and therefore lead to a party being timed-out.
     *  @param transactionID The index of the transaction.
     */
    function payArbitrationFee(uint256 transactionID)
        external
        payable
        nonReentrant
        onlyValidTransaction(transactionID)
    {
        Transaction storage transaction = _transactions[transactionID];

        if (transaction.status >= Status.DisputeCreated) {
            revert InvalidStatus();
        }

        if ((msg.sender != transaction.client) && (msg.sender != transaction.freelancer)) {
            revert InvalidCaller();
        }

        // Freeze the arbitration cost at the first payArbitrationFee so a mid-dispute
        // price change cannot leave the contract unable to refund the winner.
        uint256 arbitrationCost_;
        if (transaction.clientFee == 0 && transaction.freelancerFee == 0) {
            arbitrationCost_ = arbitratorData.arbitrator.arbitrationCost(arbitratorData.extraData);
            transaction.arbitrationCost = arbitrationCost_;
        } else {
            arbitrationCost_ = transaction.arbitrationCost;
        }

        if (msg.value != arbitrationCost_) {
            revert InvalidAmount();
        }

        transaction.lastInteraction = uint32(block.timestamp);

        if (msg.sender == transaction.client) {
            if (transaction.clientFee != 0) {
                revert AlreadyPaid();
            }
            transaction.clientFee = msg.value;
        } else {
            if (transaction.freelancerFee != 0) {
                revert AlreadyPaid();
            }
            transaction.freelancerFee = msg.value;
        }

        address other = msg.sender == transaction.client ? transaction.freelancer : transaction.client;

        if (
            ((msg.sender == transaction.client) && (transaction.freelancerFee != 0))
                || ((msg.sender == transaction.freelancer) && (transaction.clientFee != 0))
        ) {
            transaction.status = Status.DisputeCreated;
            transaction.disputeID = arbitratorData.arbitrator.createDispute{value: arbitrationCost_}(
                AMOUNT_OF_CHOICES, arbitratorData.extraData
            );
            transactionIdByDisputeId[transaction.disputeID] = transactionID;
            emit DisputeCreated(transactionID, transaction.disputeID, other);
        } else {
            transaction.status = msg.sender == transaction.client ? Status.WaitingFreelancer : Status.WaitingClient;
            emit HasToPayFee(transactionID, other);
        }
    }

    /**
     * @dev A function to handle a scenario where a party fails to pay the fee within the defined time limit.
     *  It allows for a timeout period and then reimburses the other party.
     *  Only a valid transaction can call this function.
     *  @param transactionID The ID of the transaction where a party failed to pay the fee.
     */
    function timeOut(uint256 transactionID) external nonReentrant onlyValidTransaction(transactionID) {
        Transaction storage transaction = _transactions[transactionID];

        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp - transaction.lastInteraction < arbitratorData.feeTimeout) {
            revert NoTimeout();
        }

        if (
            ((msg.sender == transaction.client) && (transaction.status == Status.WaitingFreelancer))
                || ((msg.sender == transaction.freelancer) && (transaction.status == Status.WaitingClient))
        ) {
            uint256 ruling = msg.sender == transaction.client ? CLIENT_WINS : FREELANCER_WINS;
            _executeRuling(transactionID, ruling);
            emit TimeoutExecuted(transactionID, msg.sender, ruling);
        } else {
            revert InvalidStatus();
        }
    }

    /**
     * @dev Receives and executes the final arbitrator ruling for a dispute.
     *  @param disputeID ID of the dispute in the arbitrator contract.
     *  @param ruling Ruling given by the arbitrator.
     */
    function rule(uint256 disputeID, uint256 ruling) external override nonReentrant {
        if (msg.sender != address(arbitratorData.arbitrator)) {
            revert InvalidCaller();
        }

        uint256 transactionID = transactionIdByDisputeId[disputeID];
        _requireValidTransaction(transactionID);
        Transaction storage transaction = _transactions[transactionID];

        if (transaction.status != Status.DisputeCreated) {
            revert InvalidStatus();
        }

        if (transaction.disputeID != disputeID) {
            revert InvalidTransaction();
        }

        _executeRuling(transactionID, ruling);
        emit Ruling(arbitratorData.arbitrator, disputeID, ruling);
        emit RulingAccepted(transactionID, disputeID, ruling);
    }

    /**
     * @dev A function to execute the ruling provided by the arbitrator. It distributes the funds based on the ruling.
     *  The ruling is executed in a way that it prevents reentrancy attacks.
     *  After executing the ruling, the status of the transaction is set to Resolved.
     *  @param transactionID The ID of the transaction where a ruling needs to be executed.
     *  @param ruling The ruling provided by the arbitrator. 1 means the client wins, 2 means the freelancerr wins.
     */
    function _executeRuling(uint256 transactionID, uint256 ruling) internal {
        Transaction storage transaction = _transactions[transactionID];

        // An out-of-range ruling from the arbitrator is treated as a 50/50 split
        // so a misbehaving arbitrator cannot lock the escrowed funds.
        if (ruling > FREELANCER_WINS) {
            ruling = 0;
        }

        uint256 amount = transaction.amount;
        uint256 clientArbitrationFee = transaction.clientFee;
        uint256 freelancerArbitrationFee = transaction.freelancerFee;

        transaction.amount = 0;
        transaction.clientFee = 0;
        transaction.freelancerFee = 0;
        // forge-lint: disable-next-line(unsafe-typecast)
        transaction.ruling = uint8(ruling);
        transaction.status = Status.Resolved;

        uint256 feeAmount;
        address client = transaction.client;
        address freelancer = transaction.freelancer;

        // Give the arbitration fee back.
        // Note that we use send to prevent a party from blocking the execution.
        if (ruling == CLIENT_WINS) {
            _sendOrCredit(client, transaction.token, amount);
            _sendOrCredit(client, SafeTransfer.NATIVE_TOKEN, clientArbitrationFee);
        } else if (ruling == FREELANCER_WINS) {
            feeAmount = _calculateFeeRecipientAmount(amount, transaction.feeRecipientBasisPoint);
            if (feeAmount != 0) {
                _sendOrCredit(transaction.feeRecipient, transaction.token, feeAmount);
                emit FeeRecipientPayment(transactionID, transaction.feeRecipient, transaction.token, feeAmount);
            }

            _sendOrCredit(freelancer, transaction.token, amount - feeAmount);
            _sendOrCredit(freelancer, SafeTransfer.NATIVE_TOKEN, freelancerArbitrationFee);
        } else {
            uint256 splitArbitration = clientArbitrationFee / 2;
            uint256 splitAmount = amount / 2;

            feeAmount = _calculateFeeRecipientAmount(splitAmount, transaction.feeRecipientBasisPoint);
            if (feeAmount != 0) {
                _sendOrCredit(transaction.feeRecipient, transaction.token, feeAmount);
                emit FeeRecipientPayment(transactionID, transaction.feeRecipient, transaction.token, feeAmount);
            }

            // In the case of an uneven token amount, one basic token unit can be burnt.
            _sendOrCredit(client, transaction.token, splitAmount);
            _sendOrCredit(freelancer, transaction.token, splitAmount - feeAmount);

            _sendOrCredit(client, SafeTransfer.NATIVE_TOKEN, splitArbitration);
            _sendOrCredit(freelancer, SafeTransfer.NATIVE_TOKEN, splitArbitration);
        }
    }

    function _sendOrCredit(address recipient, IERC20 token, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        if (recipient.sendToken(token, amount, false)) {
            return;
        }

        pendingWithdrawals[token][recipient] += amount;
        emit WithdrawalCredited(recipient, token, amount);
    }

    function claimWithdrawal(IERC20 token) external nonReentrant {
        uint256 amount = pendingWithdrawals[token][msg.sender];
        if (amount == 0) {
            revert InvalidAmount();
        }

        pendingWithdrawals[token][msg.sender] = 0;
        if (!msg.sender.sendToken(token, amount, true)) {
            revert TokenTransferFailed();
        }
        emit WithdrawalClaimed(msg.sender, token, amount);
    }

    // **************************** //
    // *   Utils for frontends    * //
    // **************************** //

    /**
     * @dev Get transaction by id
     *  @param transactionID The index of the transaction.
     *  @return transaction The specified transaction if does exist.
     */
    function getTransaction(uint256 transactionID)
        external
        view
        onlyValidTransaction(transactionID)
        returns (Transaction memory)
    {
        return _transactions[transactionID];
    }

    /**
     * @dev Ask arbitrator for abitration cost
     * @return Amount to be paid.
     */
    function getArbitrationCost() external view returns (uint256) {
        return arbitratorData.arbitrator.arbitrationCost(arbitratorData.extraData);
    }
}
