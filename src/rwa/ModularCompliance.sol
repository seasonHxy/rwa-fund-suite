// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RoleControl} from "./base/RoleControl.sol";
import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";
import {ICompliance} from "./interfaces/ICompliance.sol";

/// @title ModularCompliance
/// @notice A compact compliance engine with jurisdiction, blocklist, and holding-limit rules.
contract ModularCompliance is RoleControl, ICompliance {
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    bytes1 public constant SUCCESS = 0x51;
    bytes1 public constant INVALID_SENDER_IDENTITY = 0x56;
    bytes1 public constant INVALID_RECEIVER_IDENTITY = 0x57;
    bytes1 public constant COUNTRY_NOT_ALLOWED = 0x58;
    bytes1 public constant WALLET_BLOCKED = 0x59;
    bytes1 public constant HOLDING_LIMIT_EXCEEDED = 0x5a;

    IIdentityRegistry public immutable identityRegistry;
    uint256 public maxHolding;

    mapping(uint16 countryCode => bool allowed) public allowedCountry;
    mapping(address wallet => bool blocked) public blockedWallet;

    event CountryRuleSet(uint16 indexed country, bool allowed);
    event WalletBlocked(address indexed wallet, bool blocked);
    event MaxHoldingSet(uint256 previousLimit, uint256 newLimit);

    constructor(address admin, address complianceOfficer, IIdentityRegistry registry) RoleControl(admin) {
        if (complianceOfficer == address(0) || address(registry) == address(0)) {
            revert InvalidAccount();
        }
        identityRegistry = registry;
        _grantRole(COMPLIANCE_ROLE, complianceOfficer);
    }

    function setCountryAllowed(uint16 countryCode, bool allowed) external onlyRole(COMPLIANCE_ROLE) {
        allowedCountry[countryCode] = allowed;
        emit CountryRuleSet(countryCode, allowed);
    }

    function setWalletBlocked(address wallet, bool blocked) external onlyRole(COMPLIANCE_ROLE) {
        blockedWallet[wallet] = blocked;
        emit WalletBlocked(wallet, blocked);
    }

    function setMaxHolding(uint256 newLimit) external onlyRole(COMPLIANCE_ROLE) {
        uint256 previous = maxHolding;
        maxHolding = newLimit;
        emit MaxHoldingSet(previous, newLimit);
    }

    function canTransfer(address from, address to, uint256 amount, uint256 toBalance)
        external
        view
        returns (bool allowed, bytes1 reason)
    {
        if (from != address(0)) {
            if (!identityRegistry.isVerified(from)) return (false, INVALID_SENDER_IDENTITY);
            if (blockedWallet[from]) return (false, WALLET_BLOCKED);
        }
        if (to == address(0)) return (true, SUCCESS);
        return canReceive(to, amount, toBalance);
    }

    function canReceive(address to, uint256 amount, uint256 toBalance)
        public
        view
        returns (bool allowed, bytes1 reason)
    {
        if (!identityRegistry.isVerified(to)) {
            return (false, INVALID_RECEIVER_IDENTITY);
        }
        if (blockedWallet[to]) return (false, WALLET_BLOCKED);
        if (!allowedCountry[identityRegistry.country(to)]) return (false, COUNTRY_NOT_ALLOWED);
        if (maxHolding != 0 && (toBalance > maxHolding || amount > maxHolding - toBalance)) {
            return (false, HOLDING_LIMIT_EXCEEDED);
        }
        return (true, SUCCESS);
    }
}

