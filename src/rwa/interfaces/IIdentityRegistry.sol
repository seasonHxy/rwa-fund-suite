// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IIdentityRegistry {
    function isVerified(address wallet) external view returns (bool);
    function identityId(address wallet) external view returns (bytes32);
    function country(address wallet) external view returns (uint16);
}

