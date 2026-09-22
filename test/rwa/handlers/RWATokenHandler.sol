// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {RWASecurityToken} from "../../../src/rwa/RWASecurityToken.sol";

contract RWATokenHandler is Test {
    RWASecurityToken public immutable token;
    address public immutable agent;
    uint256 public immutable initialSupply;

    address[] public actors;
    uint256 public ghostMinted;
    uint256 public ghostBurned;

    constructor(RWASecurityToken token_, address agent_, address[] memory actors_, uint256 initialSupply_) {
        token = token_;
        agent = agent_;
        actors = actors_;
        initialSupply = initialSupply_;
    }

    function mint(uint256 actorSeed, uint256 rawAmount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, 1_000 ether);
        vm.prank(agent);
        token.mint(actor, amount);
        ghostMinted += amount;
    }

    function burn(uint256 actorSeed, uint256 rawAmount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, token.balanceOf(actor));
        vm.prank(agent);
        token.burn(actor, amount);
        ghostBurned += amount;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, token.balanceOf(from));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }
}

