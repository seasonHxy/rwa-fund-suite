// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {RoleControl} from "../../src/rwa/base/RoleControl.sol";
import {IdentityRegistry} from "../../src/rwa/IdentityRegistry.sol";
import {ModularCompliance} from "../../src/rwa/ModularCompliance.sol";
import {RWASecurityToken} from "../../src/rwa/RWASecurityToken.sol";

contract RWASecurityTokenTest is Test {
    address internal constant ADMIN = address(0xA11CE);
    address internal constant REGISTRAR = address(0xB0B);
    address internal constant COMPLIANCE_OFFICER = address(0xC011);
    address internal constant AGENT = address(0xA63);
    address internal constant ALICE = address(0x1001);
    address internal constant ALICE_RECOVERED = address(0x1002);
    address internal constant BOB = address(0x2001);
    address internal constant CHARLIE = address(0x3001);

    bytes32 internal constant ALICE_ID = keccak256("alice-identity");
    bytes32 internal constant BOB_ID = keccak256("bob-identity");
    uint16 internal constant US = 840;
    uint16 internal constant CN = 156;

    IdentityRegistry internal registry;
    ModularCompliance internal compliance;
    RWASecurityToken internal token;

    function setUp() public {
        registry = new IdentityRegistry(ADMIN, REGISTRAR);
        compliance = new ModularCompliance(ADMIN, COMPLIANCE_OFFICER, registry);
        token = new RWASecurityToken("Regulated Fund Share", "RFS", ADMIN, AGENT, registry, compliance);

        vm.startPrank(COMPLIANCE_OFFICER);
        compliance.setCountryAllowed(US, true);
        compliance.setCountryAllowed(CN, true);
        compliance.setMaxHolding(1_000 ether);
        vm.stopPrank();

        _register(ALICE, ALICE_ID, US);
        _register(ALICE_RECOVERED, ALICE_ID, US);
        _register(BOB, BOB_ID, CN);

        vm.prank(AGENT);
        token.mint(ALICE, 500 ether);
    }

    function test_VerifiedInvestorsCanTransfer() public {
        vm.prank(ALICE);
        token.transfer(BOB, 125 ether);

        assertEq(token.balanceOf(ALICE), 375 ether);
        assertEq(token.balanceOf(BOB), 125 ether);
        assertEq(token.totalSupply(), 500 ether);
    }

    function test_UnverifiedReceiverIsRejected() public {
        bytes1 reason = compliance.INVALID_RECEIVER_IDENTITY();
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(RWASecurityToken.ComplianceViolation.selector, reason));
        token.transfer(CHARLIE, 1 ether);

        assertEq(token.balanceOf(ALICE), 500 ether);
        assertEq(token.balanceOf(CHARLIE), 0);
    }

    function test_DisallowedCountryIsRejected() public {
        _register(CHARLIE, keccak256("charlie"), 999);
        bytes1 reason = compliance.COUNTRY_NOT_ALLOWED();

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(RWASecurityToken.ComplianceViolation.selector, reason));
        token.transfer(CHARLIE, 1 ether);
    }

    function test_BlocklistStopsTransfersInBothDirections() public {
        vm.prank(AGENT);
        token.mint(BOB, 10 ether);
        vm.prank(COMPLIANCE_OFFICER);
        compliance.setWalletBlocked(BOB, true);
        bytes1 reason = compliance.WALLET_BLOCKED();

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(RWASecurityToken.ComplianceViolation.selector, reason));
        token.transfer(BOB, 1 ether);

        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(RWASecurityToken.ComplianceViolation.selector, reason));
        token.transfer(ALICE, 1 ether);
    }

    function test_MaxHoldingIsEnforced() public {
        vm.prank(AGENT);
        token.mint(BOB, 600 ether);
        bytes1 reason = compliance.HOLDING_LIMIT_EXCEEDED();

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(RWASecurityToken.ComplianceViolation.selector, reason));
        token.transfer(BOB, 401 ether);

        assertEq(token.balanceOf(BOB), 600 ether);
    }

    function test_PartialFreezeRestrictsOnlyFrozenAmount() public {
        vm.prank(AGENT);
        token.setFrozenTokens(ALICE, 300 ether);

        vm.prank(ALICE);
        token.transfer(BOB, 200 ether);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(RWASecurityToken.InsufficientUnfrozenBalance.selector, 0, 1 ether));
        token.transfer(BOB, 1 ether);
    }

    function test_AddressFreezeStopsOrdinaryTransferButAgentCanForceTransfer() public {
        vm.prank(AGENT);
        token.setAddressFrozen(ALICE, true);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(RWASecurityToken.WalletFrozen.selector, ALICE));
        token.transfer(BOB, 10 ether);

        vm.prank(AGENT);
        token.forcedTransfer(ALICE, BOB, 10 ether);
        assertEq(token.balanceOf(BOB), 10 ether);
    }

    function test_PauseStopsOrdinaryMovementAndIssuance() public {
        vm.prank(AGENT);
        token.pause();

        vm.prank(ALICE);
        vm.expectRevert(RWASecurityToken.TokenPaused.selector);
        token.transfer(BOB, 1 ether);

        vm.prank(AGENT);
        vm.expectRevert(RWASecurityToken.TokenPaused.selector);
        token.mint(BOB, 1 ether);
    }

    function test_AddressRecoveryRequiresSameIdentity() public {
        vm.prank(AGENT);
        token.recoverAddress(ALICE, ALICE_RECOVERED);

        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(ALICE_RECOVERED), 500 ether);
        assertEq(token.totalSupply(), 500 ether);
    }

    function test_AddressRecoveryRejectsDifferentIdentity() public {
        vm.prank(AGENT);
        vm.expectRevert(RWASecurityToken.IdentityMismatch.selector);
        token.recoverAddress(ALICE, BOB);
    }

    function test_UnauthorizedMintIsRejected() public {
        bytes32 agentRole = token.AGENT_ROLE();
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(RoleControl.MissingRole.selector, ALICE, agentRole));
        token.mint(ALICE, 1 ether);
    }

    function testFuzz_TransferConservesSupply(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 0, 500 ether);
        uint256 supplyBefore = token.totalSupply();

        vm.prank(ALICE);
        token.transfer(BOB, amount);

        assertEq(token.balanceOf(ALICE) + token.balanceOf(BOB), supplyBefore);
        assertEq(token.totalSupply(), supplyBefore);
    }

    function _register(address wallet, bytes32 identity, uint16 country) internal {
        vm.prank(REGISTRAR);
        registry.registerInvestor(wallet, identity, country, uint64(block.timestamp + 365 days));
    }
}
