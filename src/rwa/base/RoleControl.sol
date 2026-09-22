// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title RoleControl
/// @notice Minimal role-based access control used to keep this training project self-contained.
/// @dev Production deployments should replace this with a pinned, audited access-control library.
abstract contract RoleControl {
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);

    mapping(bytes32 role => mapping(address account => bool granted)) private _roles;

    error InvalidAccount();
    error MissingRole(address account, bytes32 role);

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    constructor(address initialAdmin) {
        if (initialAdmin == address(0)) revert InvalidAccount();
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
    }

    modifier onlyRole(bytes32 role) {
        if (!hasRole(role, msg.sender)) revert MissingRole(msg.sender, role);
        _;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    function grantRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert InvalidAccount();
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_roles[role][account]) {
            _roles[role][account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    function _grantRole(bytes32 role, address account) internal {
        if (!_roles[role][account]) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }
}

