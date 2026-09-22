// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RoleControl} from "./base/RoleControl.sol";
import {ReentrancyGuard} from "./base/ReentrancyGuard.sol";
import {SafeTransferLib} from "./base/SafeTransferLib.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";
import {RWASecurityToken} from "./RWASecurityToken.sol";

/// @title TokenizedFund
/// @notice Asynchronous subscription and redemption workflow using a regulated share token.
contract TokenizedFund is RoleControl, ReentrancyGuard {
    using SafeTransferLib for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant NAV_ORACLE_ROLE = keccak256("NAV_ORACLE_ROLE");

    uint256 public constant SHARE_SCALE = 1e18;

    enum OrderStatus {
        None,
        Pending,
        Processed,
        Cancelled
    }

    struct Subscription {
        address investor;
        uint256 assets;
        uint256 minShares;
        uint256 sharesIssued;
        OrderStatus status;
    }

    struct Redemption {
        address investor;
        uint256 shares;
        uint256 minAssets;
        uint256 assetsPaid;
        OrderStatus status;
    }

    IERC20 public immutable asset;
    RWASecurityToken public immutable shareToken;
    IIdentityRegistry public immutable identityRegistry;

    uint256 public navPerShare;
    uint256 public nextSubscriptionId = 1;
    uint256 public nextRedemptionId = 1;
    uint256 public pendingSubscriptionAssets;
    bool public paused;

    mapping(uint256 id => Subscription order) public subscriptions;
    mapping(uint256 id => Redemption order) public redemptions;

    error FundPaused();
    error InvalidAmount();
    error InvalidNAV();
    error InvestorNotVerified();
    error InvalidOrder();
    error InvalidOrderOwner();
    error SlippageExceeded(uint256 actual, uint256 minimum);
    error InsufficientLiquidAssets(uint256 available, uint256 required);

    event NAVUpdated(uint256 previousNAV, uint256 newNAV);
    event SubscriptionRequested(uint256 indexed id, address indexed investor, uint256 assets, uint256 minShares);
    event SubscriptionProcessed(uint256 indexed id, address indexed investor, uint256 assets, uint256 shares);
    event SubscriptionCancelled(uint256 indexed id, address indexed investor);
    event RedemptionRequested(uint256 indexed id, address indexed investor, uint256 shares, uint256 minAssets);
    event RedemptionProcessed(uint256 indexed id, address indexed investor, uint256 shares, uint256 assets);
    event RedemptionCancelled(uint256 indexed id, address indexed investor);
    event PauseChanged(bool paused);

    constructor(
        address admin,
        address manager,
        address navOracle,
        IERC20 paymentAsset,
        RWASecurityToken regulatedShareToken,
        IIdentityRegistry registry,
        uint256 initialNAV
    ) RoleControl(admin) {
        if (
            manager == address(0) || navOracle == address(0) || address(paymentAsset) == address(0)
                || address(regulatedShareToken) == address(0) || address(registry) == address(0)
        ) revert InvalidAccount();
        if (initialNAV == 0) revert InvalidNAV();
        asset = paymentAsset;
        shareToken = regulatedShareToken;
        identityRegistry = registry;
        navPerShare = initialNAV;
        _grantRole(MANAGER_ROLE, manager);
        _grantRole(NAV_ORACLE_ROLE, navOracle);
    }

    modifier whenNotPaused() {
        if (paused) revert FundPaused();
        _;
    }

    modifier onlyVerified() {
        if (!identityRegistry.isVerified(msg.sender)) revert InvestorNotVerified();
        _;
    }

    function previewSubscription(uint256 assets) public view returns (uint256) {
        return assets * SHARE_SCALE / navPerShare;
    }

    function previewRedemption(uint256 shares) public view returns (uint256) {
        return shares * navPerShare / SHARE_SCALE;
    }

    function requestSubscription(uint256 assets, uint256 minShares)
        external
        nonReentrant
        whenNotPaused
        onlyVerified
        returns (uint256 id)
    {
        if (assets == 0 || minShares == 0) revert InvalidAmount();
        id = nextSubscriptionId++;
        subscriptions[id] = Subscription(msg.sender, assets, minShares, 0, OrderStatus.Pending);
        pendingSubscriptionAssets += assets;
        asset.safeTransferFrom(msg.sender, address(this), assets);
        emit SubscriptionRequested(id, msg.sender, assets, minShares);
    }

    function processSubscription(uint256 id) external nonReentrant onlyRole(MANAGER_ROLE) {
        Subscription storage order = subscriptions[id];
        if (order.status != OrderStatus.Pending) revert InvalidOrder();
        uint256 shares = previewSubscription(order.assets);
        if (shares < order.minShares) revert SlippageExceeded(shares, order.minShares);
        order.status = OrderStatus.Processed;
        order.sharesIssued = shares;
        pendingSubscriptionAssets -= order.assets;
        shareToken.mint(order.investor, shares);
        emit SubscriptionProcessed(id, order.investor, order.assets, shares);
    }

    function cancelSubscription(uint256 id) external nonReentrant {
        Subscription storage order = subscriptions[id];
        if (order.status != OrderStatus.Pending) revert InvalidOrder();
        if (order.investor != msg.sender) revert InvalidOrderOwner();
        order.status = OrderStatus.Cancelled;
        pendingSubscriptionAssets -= order.assets;
        asset.safeTransfer(order.investor, order.assets);
        emit SubscriptionCancelled(id, order.investor);
    }

    function requestRedemption(uint256 shares, uint256 minAssets)
        external
        nonReentrant
        whenNotPaused
        onlyVerified
        returns (uint256 id)
    {
        if (shares == 0 || minAssets == 0) revert InvalidAmount();
        id = nextRedemptionId++;
        redemptions[id] = Redemption(msg.sender, shares, minAssets, 0, OrderStatus.Pending);
        IERC20(address(shareToken)).safeTransferFrom(msg.sender, address(this), shares);
        emit RedemptionRequested(id, msg.sender, shares, minAssets);
    }

    function processRedemption(uint256 id) external nonReentrant onlyRole(MANAGER_ROLE) {
        Redemption storage order = redemptions[id];
        if (order.status != OrderStatus.Pending) revert InvalidOrder();
        uint256 assets = previewRedemption(order.shares);
        if (assets < order.minAssets) revert SlippageExceeded(assets, order.minAssets);
        uint256 assetBalance = asset.balanceOf(address(this));
        uint256 available = assetBalance > pendingSubscriptionAssets ? assetBalance - pendingSubscriptionAssets : 0;
        if (available < assets) revert InsufficientLiquidAssets(available, assets);
        order.status = OrderStatus.Processed;
        order.assetsPaid = assets;
        shareToken.burn(address(this), order.shares);
        asset.safeTransfer(order.investor, assets);
        emit RedemptionProcessed(id, order.investor, order.shares, assets);
    }

    function cancelRedemption(uint256 id) external nonReentrant {
        Redemption storage order = redemptions[id];
        if (order.status != OrderStatus.Pending) revert InvalidOrder();
        if (order.investor != msg.sender) revert InvalidOrderOwner();
        order.status = OrderStatus.Cancelled;
        IERC20(address(shareToken)).safeTransfer(order.investor, order.shares);
        emit RedemptionCancelled(id, order.investor);
    }

    function setNAV(uint256 newNAV) external onlyRole(NAV_ORACLE_ROLE) {
        if (newNAV == 0) revert InvalidNAV();
        uint256 previous = navPerShare;
        navPerShare = newNAV;
        emit NAVUpdated(previous, newNAV);
    }

    function setPaused(bool newPaused) external onlyRole(MANAGER_ROLE) {
        paused = newPaused;
        emit PauseChanged(newPaused);
    }
}
