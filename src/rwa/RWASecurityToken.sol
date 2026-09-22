// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RoleControl} from "./base/RoleControl.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";
import {ICompliance} from "./interfaces/ICompliance.sol";

/// @title RWASecurityToken
/// @notice Educational, ERC-20-compatible permissioned token inspired by ERC-3643 and ERC-1400.
/// @dev This is not a complete implementation of either standard and is not production ready.
contract RWASecurityToken is RoleControl, IERC20 {
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    IIdentityRegistry public identityRegistry;
    ICompliance public compliance;
    bool public paused;

    mapping(address account => uint256 balance) private _balances;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;
    mapping(address wallet => bool frozen) public frozenWallet;
    mapping(address wallet => uint256 amount) public frozenTokens;

    error InvalidReceiver();
    error InvalidRegistry();
    error InvalidCompliance();
    error InsufficientBalance(uint256 available, uint256 required);
    error InsufficientAllowance(uint256 available, uint256 required);
    error InsufficientUnfrozenBalance(uint256 available, uint256 required);
    error ComplianceViolation(bytes1 reason);
    error TokenPaused();
    error WalletFrozen(address wallet);
    error InvalidFrozenAmount();
    error IdentityMismatch();

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event AddressFrozen(address indexed wallet, bool frozen, address indexed agent);
    event TokensFrozen(address indexed wallet, uint256 amount, address indexed agent);
    event RecoverySuccess(
        address indexed lostWallet, address indexed newWallet, bytes32 indexed identityId, uint256 amount
    );
    event Paused(address indexed agent);
    event Unpaused(address indexed agent);
    event IdentityRegistrySet(address indexed previousRegistry, address indexed newRegistry);
    event ComplianceSet(address indexed previousCompliance, address indexed newCompliance);

    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        address admin,
        address agent,
        IIdentityRegistry registry,
        ICompliance complianceEngine
    ) RoleControl(admin) {
        if (agent == address(0)) revert InvalidAccount();
        if (address(registry) == address(0)) revert InvalidRegistry();
        if (address(complianceEngine) == address(0)) revert InvalidCompliance();
        name = tokenName;
        symbol = tokenSymbol;
        identityRegistry = registry;
        compliance = complianceEngine;
        _grantRole(AGENT_ROLE, agent);
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        if (spender == address(0)) revert InvalidReceiver();
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance(allowed, amount);
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external onlyRole(AGENT_ROLE) {
        _requireNotPaused();
        if (to == address(0)) revert InvalidReceiver();
        _enforceCanReceive(to, amount, _balances[to]);
        totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(AGENT_ROLE) {
        _requireNotPaused();
        uint256 balance = _balances[from];
        if (balance < amount) revert InsufficientBalance(balance, amount);
        _balances[from] = balance - amount;
        totalSupply -= amount;
        if (frozenTokens[from] > _balances[from]) frozenTokens[from] = _balances[from];
        emit Transfer(from, address(0), amount);
    }

    /// @notice Regulatory transfer that bypasses wallet freezes and allowances but still validates the receiver.
    function forcedTransfer(address from, address to, uint256 amount) external onlyRole(AGENT_ROLE) {
        if (to == address(0)) revert InvalidReceiver();
        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) revert InsufficientBalance(fromBalance, amount);
        uint256 toBase = from == to ? _balances[to] - amount : _balances[to];
        _enforceCanReceive(to, amount, toBase);
        _moveUnchecked(from, to, amount);
    }

    function setAddressFrozen(address wallet, bool frozen) external onlyRole(AGENT_ROLE) {
        if (wallet == address(0)) revert InvalidReceiver();
        frozenWallet[wallet] = frozen;
        emit AddressFrozen(wallet, frozen, msg.sender);
    }

    function setFrozenTokens(address wallet, uint256 amount) external onlyRole(AGENT_ROLE) {
        if (amount > _balances[wallet]) revert InvalidFrozenAmount();
        frozenTokens[wallet] = amount;
        emit TokensFrozen(wallet, amount, msg.sender);
    }

    function recoverAddress(address lostWallet, address newWallet) external onlyRole(AGENT_ROLE) {
        if (lostWallet == address(0) || newWallet == address(0) || lostWallet == newWallet) {
            revert InvalidReceiver();
        }
        bytes32 lostIdentity = identityRegistry.identityId(lostWallet);
        if (
            lostIdentity == bytes32(0) || lostIdentity != identityRegistry.identityId(newWallet)
                || !identityRegistry.isVerified(newWallet)
        ) revert IdentityMismatch();

        uint256 amount = _balances[lostWallet];
        _enforceCanReceive(newWallet, amount, _balances[newWallet]);
        uint256 frozen = frozenTokens[lostWallet];
        _balances[lostWallet] = 0;
        frozenTokens[lostWallet] = 0;
        _balances[newWallet] += amount;
        frozenTokens[newWallet] += frozen;

        emit Transfer(lostWallet, newWallet, amount);
        emit RecoverySuccess(lostWallet, newWallet, lostIdentity, amount);
    }

    function pause() external onlyRole(AGENT_ROLE) {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyRole(AGENT_ROLE) {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function setIdentityRegistry(IIdentityRegistry newRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(newRegistry) == address(0)) revert InvalidRegistry();
        address previous = address(identityRegistry);
        identityRegistry = newRegistry;
        emit IdentityRegistrySet(previous, address(newRegistry));
    }

    function setCompliance(ICompliance newCompliance) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(newCompliance) == address(0)) revert InvalidCompliance();
        address previous = address(compliance);
        compliance = newCompliance;
        emit ComplianceSet(previous, address(newCompliance));
    }

    function canTransfer(address from, address to, uint256 amount) external view returns (bool allowed, bytes1 reason) {
        uint256 toBase = from == to && _balances[to] >= amount ? _balances[to] - amount : _balances[to];
        return compliance.canTransfer(from, to, amount, toBase);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        _requireNotPaused();
        if (to == address(0)) revert InvalidReceiver();
        if (frozenWallet[from]) revert WalletFrozen(from);
        if (frozenWallet[to]) revert WalletFrozen(to);

        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) revert InsufficientBalance(fromBalance, amount);
        uint256 available = fromBalance - frozenTokens[from];
        if (available < amount) revert InsufficientUnfrozenBalance(available, amount);

        uint256 toBase = from == to ? _balances[to] - amount : _balances[to];
        (bool allowed, bytes1 reason) = compliance.canTransfer(from, to, amount, toBase);
        if (!allowed) revert ComplianceViolation(reason);
        _moveUnchecked(from, to, amount);
    }

    function _moveUnchecked(address from, address to, uint256 amount) internal {
        _balances[from] -= amount;
        _balances[to] += amount;
        if (frozenTokens[from] > _balances[from]) frozenTokens[from] = _balances[from];
        emit Transfer(from, to, amount);
    }

    function _enforceCanReceive(address to, uint256 amount, uint256 toBalance) internal view {
        (bool allowed, bytes1 reason) = compliance.canReceive(to, amount, toBalance);
        if (!allowed) revert ComplianceViolation(reason);
    }

    function _requireNotPaused() internal view {
        if (paused) revert TokenPaused();
    }
}

