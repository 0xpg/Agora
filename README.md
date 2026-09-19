# Agora

Permissioned secondary-market protocol for tokenized real-world assets, enabling
qualified investors to trade around issuer-defined eligibility, NAV, and market
rules.

## Why not an AMM

Continuous AMMs need standing liquidity, which doesn't fit how tokenized RWAs
actually trade: thin, lumpy, and infrequent. Worse, an AMM anchored to an external
reference price (an issuer-published NAV) is structurally exposed to
[Loss-Versus-Rebalancing](https://arxiv.org/pdf/2208.06046) — whoever sees a NAV
update first trades against the pool before it reprices, extracting the gap from
LPs.

Agora is instead a **periodic uniform-price call auction**: orders escrow into a
round, the round closes on a timer, and every matched order clears at one price —
computed only after the round closes, using the NAV known at that moment. There is
no stale-price window to extract, and no LPs required. See
[`src/libraries/CallAuction.sol`](src/libraries/CallAuction.sol) for the matching
algorithm and its NatSpec for the full reasoning, including how the clearing price
is chosen within the volume-maximizing crossing interval and clamped to an
issuer-configured NAV band.

## Compliance layer

Eligibility is enforced by [`IdentityRegistry`](src/IdentityRegistry.sol), backed
by [EAS](https://attest.org) attestations rather than a bespoke KYC database — EAS
is a predeploy on every OP Stack chain including Base, and Coinbase already issues
real KYC/country attestations there via
[Coinbase Verifications](https://github.com/coinbase/verifications). A market can
require any combination of attestation schemas (e.g. Coinbase KYC + an
issuer-defined accreditation schema); `IdentityRegistry` independently re-verifies
each supplied attestation on-chain (schema, recipient, trusted attester, not
revoked, not expired) before caching a bounded-lifetime eligibility record.

Two enforcement gates, mirroring ERC-3643:

- **Token level** — [`PermissionedAssetToken`](src/PermissionedAssetToken.sol)
  blocks transfers unless both parties are currently eligible.
- **Pool level** — [`BatchAuctionMarket`](src/BatchAuctionMarket.sol) re-checks
  eligibility again at settlement, not just at order submission, so a trader who
  loses eligibility mid-round is excluded from matching and fully refunded rather
  than trading anyway.

This re-check is bounded by how fresh `IdentityRegistry`'s cache is (`maxCacheAge`,
plus each attestation's own expiry) — see
[`test/BatchAuctionMarket.t.sol`](test/BatchAuctionMarket.t.sol) for tests that
demonstrate both sides of this honestly: a revoked-then-refreshed attestation is
excluded from settlement, but revocation alone (without a refresh call) does not
retroactively invalidate an already-cached record. Set `maxCacheAge` no longer than
the round duration for assets where that matters.

An investor who becomes ineligible can still always withdraw assets they already
escrowed (a cancelled order, or the unmatched/leftover portion of a settled one) —
a compliance status change must not trap already-owned funds. See
`PermissionedAssetToken.exemptOperators` and its NatSpec.

## Contracts

| Contract | Responsibility |
|---|---|
| `IdentityRegistry` | EAS-backed eligibility cache |
| `PermissionedAssetToken` | ERC-20 tokenized security, transfer-gated on eligibility |
| `NAVOracle` | Issuer-published reference price + staleness bound |
| `CallAuction` (library) | Pure uniform-price clearing algorithm |
| `BatchAuctionMarket` | Order escrow, round lifecycle, settlement |
| `MarketFactory` + `src/factories/*` | Self-serve deployment of a full market set per issuer |

`MarketFactory` orchestrates four small per-contract sub-factories rather than
deploying everything via `new` directly — see its NatSpec for why (EIP-170's
24,576-byte contract size limit).

## Build & test

```shell
forge build
forge test -vv
```

The `CallAuction` matching algorithm has both example-based and fuzz tests
(`test/CallAuction.t.sol`); `test/BatchAuctionMarket.t.sol` covers a full
round end-to-end plus the eligibility edge cases above.

## Deploy

```shell
cp .env.example .env   # fill in EAS_ADDRESS, SETTLEMENT_TOKEN, PRIVATE_KEY, RPC_URL
forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast --verify
```

Verify `EAS_ADDRESS` (Base's EAS predeploy) and `SETTLEMENT_TOKEN` (native USDC)
against current docs before deploying — see `.env.example`.

## Status / roadmap

This is a hackathon-stage scaffold: core matching, escrow, and eligibility logic
are implemented and tested; NAV is issuer-set rather than pulled from a live feed;
`MarketFactory` deploys full instances rather than minimal proxies. Candidate next
steps: a frontend (Base OnchainKit + Smart Wallet for gasless order submission),
an indexer for round history, Clones-based factory deploys, and an ATS-N-style
disclosure tier once a market crosses a volume threshold.
