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

import {IArbitrableProxy} from "./IArbitrableProxy.sol";
import {SafeTransfer} from "./SafeTransfer.sol";

contract NerwoEscrow is Ownable, ReentrancyGuard {
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
    error NotRuled();

    // **************************** //
    // *    Contract variables    * //
    // **************************** //
    uint256 private constant AMOUNT_OF_CHOICES = 2;
    uint256 private constant CLIENT_WINS = 1;
    uint256 private constant FREELANCER_WINS = 2;
    uint256 private constant MAX_FEEBASISPOINT = 2_000; // 20%
    uint256 private constant MULTIPLIER_DIVISOR = 10_000; // Divisor parameter for multipliers.
    uint256 private constant MIN_AMOUNT = 10_000; // Minimal amount with non zero fee basis point for non zero fee

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

    mapping(IERC20 => bool) public tokens; // whitelisted ERC20 tokens

    struct ArbitratorData {
        // Time in seconds a party can take to pay arbitration
        // fees before being considered unresponding and lose the dispute.
        uint32 feeTimeout;
        IArbitrator arbitrator; // Address of the arbitrator contract.
        IArbitrableProxy proxy; // Address of the arbitrator proxy contract.
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

    // **************************** //
    // *          Events          * //
    // **************************** //

    /** @dev To be emitted when the client pays the freelancer.
     *  @param transactionID The index of the transaction.
     *  @param from The address that paid.
     *  @param to The address that received the payment.
     *  @param token The token address.
     *  @param amount The amount paid.
     */
    event Payment(
        uint256 indexed transactionID,
        address indexed from,
        address indexed to,
        IERC20 token,
        uint256 amount
    );

    /** @dev To be emitted when the freelancer reimburses the client.
     *  @param transactionID The index of the transaction.
     *  @param from The address that paid.
     *  @param to The address that received the payment.
     *  @param token The token address.
     *  @param amount The amount paid.
     */
    event Reimburse(
        uint256 indexed transactionID,
        address indexed from,
        address indexed to,
        IERC20 token,
        uint256 amount
    );

    /** @dev Indicate that a party has to pay a fee or would otherwise be considered as losing.
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

    /** @dev Emitted when a transaction is created.
     *  @param transactionID The index of the transaction.
     *  @param client The address of the client.
     *  @param freelancer The address of the freelancer.
     *  @param token The token address
     *  @param amount The initial amount in the transaction.
     */
    event TransactionCreated(
        uint256 indexed transactionID,
        address indexed client,
        address indexed freelancer,
        IERC20 token,
        uint256 amount
    );

    /** @dev To be emitted when a fee is received by the feeRecipient.
     *  @param transactionID The index of the transaction.
     *  @param recipient The fee recipient.
     *  @param token The Token Address.
     *  @param amount The amount paid.
     */
    event FeeRecipientPayment(
        uint256 indexed transactionID,
        address indexed recipient,
        IERC20 indexed token,
        uint256 amount
    );

    /** @dev To be emitted when a feeRecipient is changed.
     *  @param newFeeRecipient new fee Recipient.
     *  @param newBasisPoint new fee BasisPoint.
     */
    event FeeRecipientChanged(address indexed newFeeRecipient, uint256 newBasisPoint);

    /** @dev To be emitted when the whitelist was changed.
     *  @param token The token that was either added or removed from whitelist.
     *  @param allow Whether added or removed.
     */
    event WhitelistChanged(IERC20 indexed token, bool allow);

    /** @dev To be emitted when the contract if funded with ether by admin.
     *  @param funder The address that funded.
     *  @param amount The amount funded.
     */
    event ContractFunded(address indexed funder, uint256 amount);

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
     *  @param newOwner The initial owner
     *  @param arbitrators arbitrator and arbitratorProxy addresses.
     *  @param metaEvidenceURI Meta Evidence json IPFS URI
     *  @param feeRecipient Address which receives a share of receiver payment.
     *  @param feeRecipientBasisPoint The share of fee to be received by the feeRecipient, down to 2 decimal places as 550 = 5.5%
     *  @param supportedTokens List of whitelisted ERC20 tokens
     */
    constructor(
        address newOwner,
        address[] memory arbitrators,
        string memory metaEvidenceURI,
        address feeRecipient,
        uint256 feeRecipientBasisPoint,
        TokenAllow[] memory supportedTokens
    ) Ownable(msg.sender) {
        // cannot set newOwner here because it would break guarded calls
        setFeeRecipientAndBasisPoint(feeRecipient, feeRecipientBasisPoint);
        changeWhitelist(supportedTokens);

        arbitratorData.feeTimeout = 604800;
        arbitratorData.arbitrator = IArbitrator(arbitrators[0]);
        arbitratorData.proxy = IArbitrableProxy(arbitrators[1]);
        arbitratorData
            .extraData = hex"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003";
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

        uint16 feeRecipientBasisPoint_ = uint16(feeRecipientBasisPoint);
        if (feeRecipientBasisPoint_ > MAX_FEEBASISPOINT) {
            revert InvalidFeeBasisPoint();
        }

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
     * @dev Sets whitelisted ERC20 tokens
     * @param supportedTokens An array of TokenAllow
     */
    function changeWhitelist(TokenAllow[] memory supportedTokens) public onlyOwner {
        unchecked {
            for (uint256 i = 0; i < supportedTokens.length; i++) {
                if (address(supportedTokens[i].token) == address(0)) {
                    revert InvalidToken();
                }
                tokens[supportedTokens[i].token] = supportedTokens[i].allow;
                emit WhitelistChanged(supportedTokens[i].token, supportedTokens[i].allow);
            }
        }
    }

    /** @dev Admin function to fund the contract with ether, e.g. to unblock if the arbitrator cost changes in between (possible?)
     *  @notice It's harmless and there is no withdraw function.
     */
    receive() external payable {
        // using onlyOwner modifier trips hardhat
        // solhint-disable-next-line custom-errors
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        emit ContractFunded(msg.sender, msg.value);
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
    ) external payable returns (uint256 transactionID) {
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

        if (token == SafeTransfer.NATIVE_TOKEN) {
            // Native Token
            if (msg.value != amount) {
                revert InvalidAmount();
            }
        } else {
            // ERC20
            if (!tokens[token] || (msg.value != 0)) {
                revert InvalidToken();
            }
            // first transfer tokens to the contract
            // NOTE: user must have approved the allowance
            if (!token.safeTransferFrom(msg.sender, address(this), amount)) {
                revert TokenTransferFailed();
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
            token: token,
            amount: amount,
            disputeID: 0,
            clientFee: 0,
            freelancerFee: 0
        });

        emit TransactionCreated(transactionID, msg.sender, freelancer, token, amount);
    }

    /** @dev Pay receiver. To be called if the good or service is provided.
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

        uint256 feeAmount = calculateFeeRecipientAmount(amount);
        if (feeAmount != 0) {
            feeRecipientData.feeRecipient.sendToken(transaction.token, feeAmount, true);
            emit FeeRecipientPayment(transactionID, feeRecipientData.feeRecipient, transaction.token, feeAmount);
        }

        transaction.freelancer.sendToken(transaction.token, amount - feeAmount, false);
        emit Payment(transactionID, msg.sender, transaction.freelancer, transaction.token, amount - feeAmount);
    }

    /** @dev Reimburse sender. To be called if the good or service can't be fully provided.
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

        transaction.client.sendToken(transaction.token, amountReimbursed, false);
        emit Reimburse(transactionID, msg.sender, transaction.client, transaction.token, amountReimbursed);
    }

    /** @dev Pay the arbitration fee to raise a dispute. To be called by the client or freelancer. UNTRUSTED.
     *  Note that the arbitrator can have createDispute throw,
     *  which will make this function throw and therefore lead to a party being timed-out.
     *  @param transactionID The index of the transaction.
     */
    function payArbitrationFee(
        uint256 transactionID
    ) external payable nonReentrant onlyValidTransaction(transactionID) {
        Transaction storage transaction = _transactions[transactionID];

        if (transaction.status >= Status.DisputeCreated) {
            revert InvalidStatus();
        }

        if ((msg.sender != transaction.client) && (msg.sender != transaction.freelancer)) {
            revert InvalidCaller();
        }

        uint256 arbitrationCost_ = arbitratorData.arbitrator.arbitrationCost(arbitratorData.extraData);

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
            ((msg.sender == transaction.client) && (transaction.freelancerFee != 0)) ||
            ((msg.sender == transaction.freelancer) && (transaction.clientFee != 0))
        ) {
            transaction.status = Status.DisputeCreated;
            transaction.disputeID = arbitratorData.proxy.createDispute{value: arbitrationCost_}(
                arbitratorData.extraData,
                arbitratorData.metaEvidenceURI,
                AMOUNT_OF_CHOICES
            );
            emit DisputeCreated(transactionID, transaction.disputeID, other);
        } else {
            transaction.status = msg.sender == transaction.client ? Status.WaitingFreelancer : Status.WaitingClient;
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

        if (
            ((msg.sender == transaction.client) && (transaction.status == Status.WaitingFreelancer)) ||
            ((msg.sender == transaction.freelancer) && (transaction.status == Status.WaitingClient))
        ) {
            _executeRuling(transactionID, msg.sender == transaction.client ? CLIENT_WINS : FREELANCER_WINS);
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
        transaction.ruling = uint8(ruling);
        transaction.status = Status.Resolved;

        uint256 feeAmount;
        address client = transaction.client;
        address freelancer = transaction.freelancer;

        // Give the arbitration fee back.
        // Note that we use send to prevent a party from blocking the execution.
        if (ruling == CLIENT_WINS) {
            client.sendToken(transaction.token, amount, false);
            client.sendETH(clientArbitrationFee, false);
        } else if (ruling == FREELANCER_WINS) {
            feeAmount = calculateFeeRecipientAmount(amount);
            if (feeAmount != 0) {
                feeRecipientData.feeRecipient.sendToken(transaction.token, feeAmount, true);
                emit FeeRecipientPayment(transactionID, feeRecipientData.feeRecipient, transaction.token, feeAmount);
            }

            freelancer.sendToken(transaction.token, amount - feeAmount, false);
            freelancer.sendETH(freelancerArbitrationFee, false);
        } else {
            uint256 splitArbitration = clientArbitrationFee / 2;
            uint256 splitAmount = amount / 2;

            feeAmount = calculateFeeRecipientAmount(splitAmount);
            if (feeAmount != 0) {
                feeRecipientData.feeRecipient.sendToken(transaction.token, feeAmount, true);
                emit FeeRecipientPayment(transactionID, feeRecipientData.feeRecipient, transaction.token, feeAmount);
            }

            // In the case of an uneven token amount, one basic token unit can be burnt.
            client.sendToken(transaction.token, splitAmount, false);
            freelancer.sendToken(transaction.token, splitAmount - feeAmount, false);

            client.sendETH(splitArbitration, false);
            freelancer.sendETH(splitArbitration, false);
        }
    }

    // **************************** //
    // *   Utils for frontends    * //
    // **************************** //

    /**
     * @dev Get transaction by id
     *  @param transactionID The index of the transaction.
     *  @return transaction The specified transaction if does exist.
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
