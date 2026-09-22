// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {RoleControl} from "../../src/rwa/base/RoleControl.sol";
import {IdentityRegistry} from "../../src/rwa/IdentityRegistry.sol";
import {ModularCompliance} from "../../src/rwa/ModularCompliance.sol";
import {MockUSD} from "../../src/rwa/MockUSD.sol";
import {RWASecurityToken} from "../../src/rwa/RWASecurityToken.sol";
import {TokenizedFund} from "../../src/rwa/TokenizedFund.sol";

contract TokenizedFundTest is Test {
    address internal constant ADMIN = address(0xA11CE);
    address internal constant REGISTRAR = address(0xB0B);
    address internal constant COMPLIANCE_OFFICER = address(0xC011);
    address internal constant AGENT = address(0xA63);
    address internal constant MANAGER = address(0x6001);
    address internal constant NAV_ORACLE = address(0x6002);
    address internal constant ALICE = address(0x1001);
    address internal constant BOB = address(0x2001);
    uint16 internal constant US = 840;
    uint256 internal constant ONE_DOLLAR_NAV = 1e6;

    IdentityRegistry internal registry;
    ModularCompliance internal compliance;
    MockUSD internal asset;
    RWASecurityToken internal shares;
    TokenizedFund internal fund;

    function setUp() public {
        registry = new IdentityRegistry(ADMIN, REGISTRAR);
        compliance = new ModularCompliance(ADMIN, COMPLIANCE_OFFICER, registry);
        asset = new MockUSD(ADMIN, ADMIN);
        shares = new RWASecurityToken("Tokenized Treasury Fund", "TTF", ADMIN, AGENT, registry, compliance);
        fund = new TokenizedFund(ADMIN, MANAGER, NAV_ORACLE, asset, shares, registry, ONE_DOLLAR_NAV);

        vm.prank(COMPLIANCE_OFFICER);
        compliance.setCountryAllowed(US, true);

        _register(ALICE, keccak256("alice"));
        _register(BOB, keccak256("bob"));
        _register(address(fund), keccak256("fund-contract"));

        bytes32 agentRole = shares.AGENT_ROLE();
        vm.prank(ADMIN);
        shares.grantRole(agentRole, address(fund));

        vm.startPrank(ADMIN);
        asset.mint(ALICE, 1_000_000e6);
        asset.mint(BOB, 1_000_000e6);
        vm.stopPrank();
    }

    function test_SubscriptionLifecycle() public {
        uint256 id = _requestSubscription(ALICE, 1_000e6, 1_000 ether);

        vm.prank(MANAGER);
        fund.processSubscription(id);

        assertEq(shares.balanceOf(ALICE), 1_000 ether);
        assertEq(asset.balanceOf(address(fund)), 1_000e6);
        (,,, uint256 issued, TokenizedFund.OrderStatus status) = fund.subscriptions(id);
        assertEq(issued, 1_000 ether);
        assertEq(uint256(status), uint256(TokenizedFund.OrderStatus.Processed));
    }

    function test_SubscriptionSlippageLeavesOrderPendingAndCanBeCancelled() public {
        uint256 id = _requestSubscription(ALICE, 1_000e6, 900 ether);

        vm.prank(NAV_ORACLE);
        fund.setNAV(2e6);

        vm.prank(MANAGER);
        vm.expectRevert(abi.encodeWithSelector(TokenizedFund.SlippageExceeded.selector, 500 ether, 900 ether));
        fund.processSubscription(id);

        uint256 beforeRefund = asset.balanceOf(ALICE);
        vm.prank(ALICE);
        fund.cancelSubscription(id);
        assertEq(asset.balanceOf(ALICE), beforeRefund + 1_000e6);
    }

    function test_RedemptionLifecycle() public {
        _subscribeAndProcess(ALICE, 1_000e6);

        vm.startPrank(ALICE);
        shares.approve(address(fund), 400 ether);
        uint256 id = fund.requestRedemption(400 ether, 400e6);
        vm.stopPrank();

        uint256 balanceBefore = asset.balanceOf(ALICE);
        vm.prank(MANAGER);
        fund.processRedemption(id);

        assertEq(asset.balanceOf(ALICE), balanceBefore + 400e6);
        assertEq(shares.balanceOf(ALICE), 600 ether);
        assertEq(shares.totalSupply(), 600 ether);
    }

    function test_RedemptionCannotSpendPendingSubscriptionEscrow() public {
        _subscribeAndProcess(BOB, 500e6);
        _requestSubscription(ALICE, 1_000e6, 1_000 ether);

        vm.prank(NAV_ORACLE);
        fund.setNAV(2e6);

        vm.startPrank(BOB);
        shares.approve(address(fund), 500 ether);
        uint256 redemptionId = fund.requestRedemption(500 ether, 1_000e6);
        vm.stopPrank();

        vm.prank(MANAGER);
        vm.expectRevert(abi.encodeWithSelector(TokenizedFund.InsufficientLiquidAssets.selector, 500e6, 1_000e6));
        fund.processRedemption(redemptionId);

        assertEq(fund.pendingSubscriptionAssets(), 1_000e6);
        assertEq(asset.balanceOf(address(fund)), 1_500e6);
    }

    function test_CancelRedemptionReturnsLockedShares() public {
        _subscribeAndProcess(ALICE, 100e6);

        vm.startPrank(ALICE);
        shares.approve(address(fund), 25 ether);
        uint256 id = fund.requestRedemption(25 ether, 25e6);
        fund.cancelRedemption(id);
        vm.stopPrank();

        assertEq(shares.balanceOf(ALICE), 100 ether);
        assertEq(shares.balanceOf(address(fund)), 0);
    }

    function test_OnlyOracleCanUpdateNAV() public {
        bytes32 oracleRole = fund.NAV_ORACLE_ROLE();
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(RoleControl.MissingRole.selector, ALICE, oracleRole));
        fund.setNAV(2e6);
    }

    function test_PauseBlocksNewOrdersButNotCancellation() public {
        uint256 id = _requestSubscription(ALICE, 100e6, 100 ether);

        vm.prank(MANAGER);
        fund.setPaused(true);

        vm.startPrank(BOB);
        asset.approve(address(fund), 100e6);
        vm.expectRevert(TokenizedFund.FundPaused.selector);
        fund.requestSubscription(100e6, 100 ether);
        vm.stopPrank();

        vm.prank(ALICE);
        fund.cancelSubscription(id);
    }

    function test_UnverifiedInvestorCannotSubscribe() public {
        address outsider = address(0xBAD);
        vm.prank(ADMIN);
        asset.mint(outsider, 100e6);
        vm.startPrank(outsider);
        asset.approve(address(fund), 100e6);
        vm.expectRevert(TokenizedFund.InvestorNotVerified.selector);
        fund.requestSubscription(100e6, 100 ether);
        vm.stopPrank();
    }

    function testFuzz_ConstantNAVRoundTripPreservesAssets(uint96 rawAssets) public {
        uint256 assets = bound(uint256(rawAssets), 1, 100_000e6);
        uint256 initialBalance = asset.balanceOf(ALICE);
        _subscribeAndProcess(ALICE, assets);
        uint256 issuedShares = fund.previewSubscription(assets);

        vm.startPrank(ALICE);
        shares.approve(address(fund), issuedShares);
        uint256 id = fund.requestRedemption(issuedShares, assets);
        vm.stopPrank();

        vm.prank(MANAGER);
        fund.processRedemption(id);

        assertEq(asset.balanceOf(ALICE), initialBalance);
        assertEq(shares.balanceOf(ALICE), 0);
        assertEq(shares.totalSupply(), 0);
    }

    function _requestSubscription(address investor, uint256 assets, uint256 minShares) internal returns (uint256 id) {
        vm.startPrank(investor);
        asset.approve(address(fund), assets);
        id = fund.requestSubscription(assets, minShares);
        vm.stopPrank();
    }

    function _subscribeAndProcess(address investor, uint256 assets) internal {
        uint256 id = _requestSubscription(investor, assets, fund.previewSubscription(assets));
        vm.prank(MANAGER);
        fund.processSubscription(id);
    }

    function _register(address wallet, bytes32 identity) internal {
        vm.prank(REGISTRAR);
        registry.registerInvestor(wallet, identity, US, uint64(block.timestamp + 365 days));
    }
}
