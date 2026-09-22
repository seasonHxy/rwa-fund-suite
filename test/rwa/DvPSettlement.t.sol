// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../../src/rwa/IdentityRegistry.sol";
import {ModularCompliance} from "../../src/rwa/ModularCompliance.sol";
import {MockUSD} from "../../src/rwa/MockUSD.sol";
import {RWASecurityToken} from "../../src/rwa/RWASecurityToken.sol";
import {DvPSettlement} from "../../src/rwa/DvPSettlement.sol";

contract DvPSettlementTest is Test {
    uint256 internal constant SELLER_KEY = 0xA11CE;
    uint256 internal constant BUYER_KEY = 0xB0B;

    address internal constant ADMIN = address(0xAD);
    address internal constant REGISTRAR = address(0xBEEF);
    address internal constant COMPLIANCE_OFFICER = address(0xC011);
    address internal constant AGENT = address(0xA63);
    uint16 internal constant US = 840;

    address internal seller;
    address internal buyer;
    address internal outsider = address(0xBAD);

    IdentityRegistry internal registry;
    ModularCompliance internal compliance;
    MockUSD internal payment;
    RWASecurityToken internal security;
    DvPSettlement internal settlement;

    function setUp() public {
        seller = vm.addr(SELLER_KEY);
        buyer = vm.addr(BUYER_KEY);

        registry = new IdentityRegistry(ADMIN, REGISTRAR);
        compliance = new ModularCompliance(ADMIN, COMPLIANCE_OFFICER, registry);
        payment = new MockUSD(ADMIN, ADMIN);
        security = new RWASecurityToken("RWA Note", "NOTE", ADMIN, AGENT, registry, compliance);
        settlement = new DvPSettlement();

        vm.prank(COMPLIANCE_OFFICER);
        compliance.setCountryAllowed(US, true);
        _register(seller, keccak256("seller"));
        _register(buyer, keccak256("buyer"));

        vm.prank(AGENT);
        security.mint(seller, 1_000 ether);
        vm.prank(ADMIN);
        payment.mint(buyer, 1_000_000e6);

        vm.prank(seller);
        security.approve(address(settlement), type(uint256).max);
        vm.prank(buyer);
        payment.approve(address(settlement), type(uint256).max);
    }

    function test_AtomicSettlement() public {
        DvPSettlement.Order memory order = _defaultOrder(1);
        bytes memory signature = _sign(order);

        settlement.settle(order, signature);

        assertEq(security.balanceOf(seller), 900 ether);
        assertEq(security.balanceOf(buyer), 100 ether);
        assertEq(payment.balanceOf(seller), 10_000e6);
        assertEq(payment.balanceOf(buyer), 990_000e6);
        assertTrue(settlement.nonceUsed(seller, 1));
    }

    function test_ReplayIsRejected() public {
        DvPSettlement.Order memory order = _defaultOrder(7);
        bytes memory signature = _sign(order);
        settlement.settle(order, signature);

        vm.expectRevert(DvPSettlement.NonceAlreadyUsed.selector);
        settlement.settle(order, signature);
    }

    function test_ExpiredOrderIsRejected() public {
        DvPSettlement.Order memory order = _defaultOrder(2);
        order.deadline = block.timestamp + 1;
        bytes memory signature = _sign(order);

        vm.warp(block.timestamp + 2);
        vm.expectRevert(DvPSettlement.OrderExpired.selector);
        settlement.settle(order, signature);
    }

    function test_OrderFieldTamperingInvalidatesSignature() public {
        DvPSettlement.Order memory order = _defaultOrder(3);
        bytes memory signature = _sign(order);
        order.paymentAmount += 1;

        vm.expectRevert(DvPSettlement.InvalidSignature.selector);
        settlement.settle(order, signature);
    }

    function test_SellerCanCancelNonce() public {
        DvPSettlement.Order memory order = _defaultOrder(4);
        bytes memory signature = _sign(order);

        vm.prank(seller);
        settlement.cancelOrder(order);

        vm.expectRevert(DvPSettlement.NonceAlreadyUsed.selector);
        settlement.settle(order, signature);
    }

    function test_ComplianceFailureRollsBackPaymentLeg() public {
        vm.prank(ADMIN);
        payment.mint(outsider, 20_000e6);
        vm.prank(outsider);
        payment.approve(address(settlement), type(uint256).max);

        DvPSettlement.Order memory order = _defaultOrder(5);
        order.buyer = outsider;
        bytes memory signature = _sign(order);
        uint256 sellerPaymentBefore = payment.balanceOf(seller);
        uint256 outsiderPaymentBefore = payment.balanceOf(outsider);

        vm.expectRevert();
        settlement.settle(order, signature);

        assertEq(payment.balanceOf(seller), sellerPaymentBefore);
        assertEq(payment.balanceOf(outsider), outsiderPaymentBefore);
        assertFalse(settlement.nonceUsed(seller, 5));
    }

    function test_DomainSeparatesDifferentSettlementContracts() public {
        DvPSettlement other = new DvPSettlement();
        DvPSettlement.Order memory order = _defaultOrder(6);
        assertNotEq(settlement.hashOrder(order), other.hashOrder(order));
    }

    function _defaultOrder(uint256 nonce) internal view returns (DvPSettlement.Order memory) {
        return DvPSettlement.Order({
            seller: seller,
            buyer: buyer,
            securityToken: address(security),
            paymentToken: address(payment),
            securityAmount: 100 ether,
            paymentAmount: 10_000e6,
            nonce: nonce,
            deadline: block.timestamp + 1 days
        });
    }

    function _sign(DvPSettlement.Order memory order) internal view returns (bytes memory) {
        bytes32 digest = settlement.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SELLER_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function _register(address wallet, bytes32 identity) internal {
        vm.prank(REGISTRAR);
        registry.registerInvestor(wallet, identity, US, uint64(block.timestamp + 365 days));
    }
}

