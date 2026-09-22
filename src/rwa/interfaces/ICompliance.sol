// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ICompliance {
    function canTransfer(address from, address to, uint256 amount, uint256 toBalance)
        external
        view
        returns (bool allowed, bytes1 reason);

    function canReceive(address to, uint256 amount, uint256 toBalance)
        external
        view
        returns (bool allowed, bytes1 reason);
}

