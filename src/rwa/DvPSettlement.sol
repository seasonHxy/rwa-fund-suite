// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReentrancyGuard} from "./base/ReentrancyGuard.sol";
import {SafeTransferLib} from "./base/SafeTransferLib.sol";
import {IERC20} from "./interfaces/IERC20.sol";

/// @title DvPSettlement
/// @notice Atomic delivery-versus-payment settlement for a seller-signed, buyer-specific order.
contract DvPSettlement is ReentrancyGuard {
    using SafeTransferLib for IERC20;

    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(address seller,address buyer,address securityToken,address paymentToken,uint256 securityAmount,uint256 paymentAmount,uint256 nonce,uint256 deadline)"
    );
    bytes32 private constant NAME_HASH = keccak256("RWA DvP Settlement");
    bytes32 private constant VERSION_HASH = keccak256("1");
    uint256 private constant SECP256K1_HALF_N = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    struct Order {
        address seller;
        address buyer;
        address securityToken;
        address paymentToken;
        uint256 securityAmount;
        uint256 paymentAmount;
        uint256 nonce;
        uint256 deadline;
    }

    mapping(address seller => mapping(uint256 nonce => bool used)) public nonceUsed;

    error InvalidOrder();
    error OrderExpired();
    error NonceAlreadyUsed();
    error InvalidSignature();

    event OrderSettled(
        bytes32 indexed orderHash,
        address indexed seller,
        address indexed buyer,
        uint256 securityAmount,
        uint256 paymentAmount
    );
    event OrderCancelled(bytes32 indexed orderHash, address indexed seller, uint256 indexed nonce);

    function domainSeparator() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this)));
    }

    function hashOrder(Order calldata order) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                order.seller,
                order.buyer,
                order.securityToken,
                order.paymentToken,
                order.securityAmount,
                order.paymentAmount,
                order.nonce,
                order.deadline
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator(), structHash));
    }

    function settle(Order calldata order, bytes calldata signature) external nonReentrant {
        if (
            order.seller == address(0) || order.buyer == address(0) || order.securityToken == address(0)
                || order.paymentToken == address(0) || order.securityAmount == 0 || order.paymentAmount == 0
        ) revert InvalidOrder();
        if (block.timestamp > order.deadline) revert OrderExpired();
        if (nonceUsed[order.seller][order.nonce]) revert NonceAlreadyUsed();

        bytes32 digest = hashOrder(order);
        if (_recover(digest, signature) != order.seller) revert InvalidSignature();
        nonceUsed[order.seller][order.nonce] = true;

        IERC20(order.paymentToken).safeTransferFrom(order.buyer, order.seller, order.paymentAmount);
        IERC20(order.securityToken).safeTransferFrom(order.seller, order.buyer, order.securityAmount);

        emit OrderSettled(digest, order.seller, order.buyer, order.securityAmount, order.paymentAmount);
    }

    function cancelOrder(Order calldata order) external {
        if (msg.sender != order.seller) revert InvalidOrder();
        if (nonceUsed[order.seller][order.nonce]) revert NonceAlreadyUsed();
        nonceUsed[order.seller][order.nonce] = true;
        emit OrderCancelled(hashOrder(order), order.seller, order.nonce);
    }

    function _recover(bytes32 digest, bytes calldata signature) internal pure returns (address signer) {
        if (signature.length != 65) revert InvalidSignature();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
        if (uint256(s) > SECP256K1_HALF_N || (v != 27 && v != 28)) {
            revert InvalidSignature();
        }
        signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert InvalidSignature();
    }
}

