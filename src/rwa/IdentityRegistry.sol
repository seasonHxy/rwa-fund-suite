// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RoleControl} from "./base/RoleControl.sol";
import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";

/// @title IdentityRegistry
/// @notice Training-oriented identity registry inspired by the ERC-3643 separation of identity and token logic.
contract IdentityRegistry is RoleControl, IIdentityRegistry {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    struct Investor {
        bytes32 identityId;
        uint16 country;
        uint64 validUntil;
        bool active;
    }

    mapping(address wallet => Investor investor) public investors;

    error InvalidIdentity();
    error InvalidCountry();
    error IdentityExpired();
    error IdentityNotFound();

    event InvestorRegistered(
        address indexed wallet, bytes32 indexed identityId, uint16 indexed country, uint64 validUntil
    );
    event InvestorRevoked(address indexed wallet, bytes32 indexed identityId);

    constructor(address admin, address registrar) RoleControl(admin) {
        if (registrar == address(0)) revert InvalidAccount();
        _grantRole(REGISTRAR_ROLE, registrar);
    }

    function registerInvestor(address wallet, bytes32 investorIdentityId, uint16 investorCountry, uint64 validUntil)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        if (wallet == address(0) || investorIdentityId == bytes32(0)) revert InvalidIdentity();
        if (investorCountry == 0) revert InvalidCountry();
        if (validUntil <= block.timestamp) revert IdentityExpired();

        investors[wallet] =
            Investor({identityId: investorIdentityId, country: investorCountry, validUntil: validUntil, active: true});

        emit InvestorRegistered(wallet, investorIdentityId, investorCountry, validUntil);
    }

    function revokeInvestor(address wallet) external onlyRole(REGISTRAR_ROLE) {
        Investor storage investor = investors[wallet];
        if (investor.identityId == bytes32(0)) revert IdentityNotFound();
        investor.active = false;
        emit InvestorRevoked(wallet, investor.identityId);
    }

    function isVerified(address wallet) public view returns (bool) {
        Investor memory investor = investors[wallet];
        return investor.active && investor.identityId != bytes32(0) && investor.validUntil >= block.timestamp;
    }

    function identityId(address wallet) external view returns (bytes32) {
        return investors[wallet].identityId;
    }

    function country(address wallet) external view returns (uint16) {
        return investors[wallet].country;
    }
}

