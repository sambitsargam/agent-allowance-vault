// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                        MINIMAL INTERFACES
//////////////////////////////////////////////////////////////*/

/// @dev Minimal ERC20 interface used by the vault.
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/*//////////////////////////////////////////////////////////////
                            SAFE ERC20
//////////////////////////////////////////////////////////////*/

/// @dev Handles non-standard ERC20 tokens that return no value or `false`.
library SafeERC20 {
    error SafeERC20FailedOperation(address token);

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        (bool success, bytes memory returndata) = address(token).call(data);
        if (!success || (returndata.length != 0 && !abi.decode(returndata, (bool)))) {
            revert SafeERC20FailedOperation(address(token));
        }
        // Token address must contain code, otherwise an empty-return call would silently pass.
        if (address(token).code.length == 0) revert SafeERC20FailedOperation(address(token));
    }
}

/*//////////////////////////////////////////////////////////////
                        REENTRANCY GUARD
//////////////////////////////////////////////////////////////*/

/// @dev Single-slot reentrancy guard.
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    error ReentrancyGuardReentrantCall();

    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrancyGuardReentrantCall();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

/*//////////////////////////////////////////////////////////////
                       AGENT ALLOWANCE VAULT
//////////////////////////////////////////////////////////////*/

/// @title  AgentAllowanceVault
/// @notice A custody vault that lets an owner delegate *bounded* spending power to
///         autonomous AI agents. Each agent receives a rolling spending cap, an
///         optional per-transaction maximum, and an expiry. Payments within the
///         budget execute instantly; payments above the budget are queued and
///         require explicit owner approval. The owner can pause, revoke, or
///         withdraw at any time. Built for the Pharos Skill Engine.
/// @dev    Custodies ONE asset, set immutably at deployment:
///         - `asset == address(0)` → native PHRS (the chain's gas token)
///         - `asset == <ERC20>`    → that ERC20 token
contract AgentAllowanceVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    struct Allowance {
        uint256 cap;          // max spendable per period
        uint256 maxPerTx;     // max per single payment (0 = no per-tx limit)
        uint256 period;       // length of a budget period in seconds
        uint256 spent;        // amount spent in the current period
        uint256 periodStart;  // timestamp the current period began
        uint64  expiry;       // allowance is invalid at/after this time (0 = never)
        bool    active;       // whether the agent may spend at all
    }

    struct PendingPayment {
        address agent;        // agent that requested the payment
        address recipient;    // payout destination
        uint256 amount;       // payout amount
        uint64  createdAt;    // request timestamp
        bool    executed;     // settled by owner
        bool    cancelled;    // cancelled by owner or agent
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The custodied asset. `address(0)` means native PHRS.
    address public immutable asset;

    address public owner;
    address public pendingOwner;
    bool    public paused;

    mapping(address agent => Allowance) public allowances;
    mapping(uint256 id => PendingPayment) public pendingPayments;
    uint256 public nextPaymentId;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposited(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event AllowanceGranted(
        address indexed agent, uint256 cap, uint256 maxPerTx, uint256 period, uint64 expiry
    );
    event AllowanceRevoked(address indexed agent);
    event Paid(address indexed agent, address indexed recipient, uint256 amount, uint256 remaining);
    event PaymentRequested(
        uint256 indexed id, address indexed agent, address indexed recipient, uint256 amount
    );
    event PaymentApproved(uint256 indexed id, address indexed recipient, uint256 amount);
    event PaymentCancelled(uint256 indexed id);
    event Paused(bool paused);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotOwner();
    error NotAuthorizedAgent();
    error ZeroAddress();
    error ZeroAmount();
    error ContractPaused();
    error AllowanceExpired();
    error PerTxLimitExceeded(uint256 amount, uint256 maxPerTx);
    error BudgetExceeded(uint256 amount, uint256 remaining);
    error InsufficientVaultBalance(uint256 amount, uint256 balance);
    error InvalidPeriod();
    error PaymentNotFound();
    error PaymentAlreadySettled();
    error NotRequesterOrOwner();
    error NotNativeVault();
    error NotERC20Vault();
    error NativeTransferFailed(address to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param asset_ Custodied asset. Pass `address(0)` for native PHRS, or an ERC20 address.
    constructor(address asset_) {
        asset = asset_;
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /// @notice True if this vault custodies native PHRS rather than an ERC20.
    function isNative() public view returns (bool) {
        return asset == address(0);
    }

    /*//////////////////////////////////////////////////////////////
                              FUNDING
    //////////////////////////////////////////////////////////////*/

    /// @notice Fund a **native PHRS** vault. Send PHRS as `msg.value`.
    function depositNative() external payable nonReentrant {
        if (asset != address(0)) revert NotNativeVault();
        if (msg.value == 0) revert ZeroAmount();
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Accept plain native transfers as deposits (native vaults only).
    receive() external payable {
        if (asset != address(0)) revert NotNativeVault();
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Fund an **ERC20** vault. Caller must have approved this contract for `amount`.
    function deposit(uint256 amount) external nonReentrant {
        if (asset == address(0)) revert NotERC20Vault();
        if (amount == 0) revert ZeroAmount();
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount);
    }

    /// @notice Owner withdraws funds from the vault.
    function withdraw(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 bal = _balance();
        if (amount > bal) revert InsufficientVaultBalance(amount, bal);
        _payout(to, amount);
        emit Withdrawn(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          ALLOWANCE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Grant or overwrite an agent's spending allowance.
    /// @param agent    Address authorized to spend on the owner's behalf.
    /// @param cap      Maximum total spend per rolling period.
    /// @param maxPerTx Maximum per single payment (0 = unlimited per-tx, still bounded by cap).
    /// @param period   Length of a budget period in seconds (must be > 0).
    /// @param expiry   Unix time after which the allowance is invalid (0 = never expires).
    function grantAllowance(
        address agent,
        uint256 cap,
        uint256 maxPerTx,
        uint256 period,
        uint64 expiry
    ) external onlyOwner {
        if (agent == address(0)) revert ZeroAddress();
        if (period == 0) revert InvalidPeriod();

        allowances[agent] = Allowance({
            cap: cap,
            maxPerTx: maxPerTx,
            period: period,
            spent: 0,
            periodStart: block.timestamp,
            expiry: expiry,
            active: true
        });

        emit AllowanceGranted(agent, cap, maxPerTx, period, expiry);
    }

    /// @notice Immediately revoke an agent's ability to spend.
    function revokeAllowance(address agent) external onlyOwner {
        allowances[agent].active = false;
        emit AllowanceRevoked(agent);
    }

    /*//////////////////////////////////////////////////////////////
                          AGENT SPENDING
    //////////////////////////////////////////////////////////////*/

    /// @notice Agent pays `recipient` `amount` from the vault, within its budget.
    /// @dev    Reverts if the payment would exceed the per-tx limit or remaining budget.
    ///         For over-budget payments, use {requestPayment} instead.
    function pay(address recipient, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 remaining)
    {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        Allowance storage a = _validatedAllowance(msg.sender);

        if (a.maxPerTx != 0 && amount > a.maxPerTx) {
            revert PerTxLimitExceeded(amount, a.maxPerTx);
        }

        // Roll the budget period forward if it has elapsed, persisting the reset.
        if (block.timestamp >= a.periodStart + a.period) {
            a.spent = 0;
            a.periodStart = block.timestamp;
        }

        uint256 rem = a.cap > a.spent ? a.cap - a.spent : 0;
        if (amount > rem) revert BudgetExceeded(amount, rem);

        uint256 bal = _balance();
        if (amount > bal) revert InsufficientVaultBalance(amount, bal);

        // Effects before interaction (checks-effects-interactions).
        a.spent += amount;
        remaining = rem - amount;

        _payout(recipient, amount);
        emit Paid(msg.sender, recipient, amount, remaining);
    }

    /// @notice Agent queues an over-budget payment for owner approval.
    /// @dev    Does not move funds; settlement happens in {approvePayment}.
    function requestPayment(address recipient, uint256 amount)
        external
        whenNotPaused
        returns (uint256 id)
    {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        // Must be an authorized (active, unexpired) agent to queue requests.
        _validatedAllowance(msg.sender);

        id = nextPaymentId++;
        pendingPayments[id] = PendingPayment({
            agent: msg.sender,
            recipient: recipient,
            amount: amount,
            createdAt: uint64(block.timestamp),
            executed: false,
            cancelled: false
        });

        emit PaymentRequested(id, msg.sender, recipient, amount);
    }

    /// @notice Owner approves and settles a queued payment.
    /// @dev    Bypasses the agent's budget (this *is* the explicit owner override),
    ///         but still respects pause and vault balance.
    function approvePayment(uint256 id) external onlyOwner nonReentrant whenNotPaused {
        PendingPayment storage p = pendingPayments[id];
        if (p.recipient == address(0)) revert PaymentNotFound();
        if (p.executed || p.cancelled) revert PaymentAlreadySettled();

        uint256 bal = _balance();
        if (p.amount > bal) revert InsufficientVaultBalance(p.amount, bal);

        p.executed = true; // effects before interaction
        _payout(p.recipient, p.amount);
        emit PaymentApproved(id, p.recipient, p.amount);
    }

    /// @notice Cancel a queued payment. Callable by the requesting agent or the owner.
    function cancelPayment(uint256 id) external {
        PendingPayment storage p = pendingPayments[id];
        if (p.recipient == address(0)) revert PaymentNotFound();
        if (p.executed || p.cancelled) revert PaymentAlreadySettled();
        if (msg.sender != owner && msg.sender != p.agent) revert NotRequesterOrOwner();

        p.cancelled = true;
        emit PaymentCancelled(id);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN CONTROLS
    //////////////////////////////////////////////////////////////*/

    /// @notice Pause or unpause all agent spending and payment settlement.
    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
        emit Paused(paused_);
    }

    /// @notice Begin a two-step ownership transfer. `newOwner` must call {acceptOwnership}.
    function transferOwnership(address newOwner) external onlyOwner {
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /// @notice Complete a two-step ownership transfer.
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotOwner();
        address previous = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Current asset balance held by the vault (native PHRS or ERC20).
    function vaultBalance() external view returns (uint256) {
        return _balance();
    }

    /// @notice Remaining spendable budget for `agent` in the current period.
    /// @dev    Accounts for an elapsed period (resets to full cap) without writing state.
    function remainingAllowance(address agent) external view returns (uint256) {
        Allowance storage a = allowances[agent];
        if (!a.active) return 0;
        if (a.expiry != 0 && block.timestamp >= a.expiry) return 0;
        return _remaining(a);
    }

    /// @notice Full allowance record for `agent`.
    function getAllowance(address agent) external view returns (Allowance memory) {
        return allowances[agent];
    }

    /// @notice Full record for a queued payment.
    function getPendingPayment(uint256 id) external view returns (PendingPayment memory) {
        return pendingPayments[id];
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Validates that the caller is an active, unexpired agent and returns its record.
    function _validatedAllowance(address agent) private view returns (Allowance storage a) {
        a = allowances[agent];
        if (!a.active) revert NotAuthorizedAgent();
        if (a.expiry != 0 && block.timestamp >= a.expiry) revert AllowanceExpired();
    }

    /// @dev Remaining budget, treating an elapsed period as a fresh full cap.
    function _remaining(Allowance storage a) private view returns (uint256) {
        if (block.timestamp >= a.periodStart + a.period) {
            return a.cap; // period rolled over: full cap available
        }
        return a.cap > a.spent ? a.cap - a.spent : 0;
    }

    /// @dev The vault's current balance of the custodied asset.
    function _balance() private view returns (uint256) {
        return asset == address(0) ? address(this).balance : IERC20(asset).balanceOf(address(this));
    }

    /// @dev Pay out the custodied asset to `to`. Native uses a bounded `call`; ERC20 uses SafeERC20.
    function _payout(address to, uint256 amount) private {
        if (asset == address(0)) {
            (bool ok, ) = payable(to).call{value: amount}("");
            if (!ok) revert NativeTransferFailed(to, amount);
        } else {
            IERC20(asset).safeTransfer(to, amount);
        }
    }
}
