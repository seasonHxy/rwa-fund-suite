# RWA Fund Suite

A Solidity reference implementation for compliant tokenized fund issuance, subscription, redemption, and delivery-versus-payment settlement.

The system combines an identity registry, modular transfer restrictions, a permissioned ERC-20-compatible share token, asynchronous fund orders, and signed atomic settlement. It is designed to make asset flows, role boundaries, and security properties explicit and testable.

> This repository is not a complete ERC-3643 or ERC-1400 implementation. It has not been independently audited and must not be deployed to production without further review and hardening.

## Architecture

| Contract | Responsibility |
| --- | --- |
| `IdentityRegistry` | Investor identity, jurisdiction, validity, and revocation |
| `ModularCompliance` | Jurisdiction rules, wallet blocking, and holding limits |
| `RWASecurityToken` | Restricted transfers, issuance, redemption, freezes, recovery, and forced transfers |
| `TokenizedFund` | NAV-based asynchronous subscriptions and redemptions |
| `DvPSettlement` | Buyer-specific, seller-signed atomic security/payment settlement |
| `MockUSD` | Six-decimal payment asset used by tests |

## Core flows

### Subscription

1. A verified investor deposits payment assets and specifies `minShares`.
2. The assets remain reserved while the order is pending.
3. A fund manager processes the order at the current NAV.
4. Regulated fund shares are minted to the investor.

### Redemption

1. A verified investor escrows fund shares and specifies `minAssets`.
2. A fund manager checks NAV, slippage, and available liquidity.
3. The escrowed shares are burned and payment assets are returned.
4. Pending subscription assets are excluded from redemption liquidity.

### Delivery versus payment

A seller signs an order containing the buyer, both token addresses, both amounts, a nonce, and a deadline. Settlement transfers payment and securities atomically. The EIP-712-style domain binds the signature to the chain and settlement contract.

## Security testing

The Foundry test suite includes:

- unit tests for success and failure paths;
- role and compliance boundary tests;
- fuzz tests for supply conservation and NAV round trips;
- replay, signature-tampering, expiry, and atomic rollback tests;
- handler-based invariant tests with ghost accounting;
- a regression test proving pending subscription escrow cannot fund redemptions.

Run the complete suite:

```bash
forge fmt --check
forge build
forge test -vv
```

Run only the RWA tests or coverage:

```bash
forge test --match-path 'test/rwa/*'
forge coverage --match-path 'test/rwa/*' --report summary
```

## Local deployment

```bash
anvil
forge script script/DeployRWAFund.s.sol:DeployRWAFund \
  --rpc-url http://127.0.0.1:8545 \
  --private-key "$PRIVATE_KEY" \
  --broadcast
```

The deployment script assigns all operational roles to the broadcaster for local use. A real deployment should separate administrator, registrar, compliance officer, token agent, fund manager, and NAV publisher roles across governed accounts.

## Documentation

- [Business specification and invariants](docs/SPEC.md)
- [Threat model and security boundaries](docs/SECURITY.md)
- [ERC-3643 and ERC-1400 gap analysis](docs/STANDARDS-MAP.md)

## License

MIT
