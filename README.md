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

## Fund conservation

`test/invariant/BatchAuctionMarket.invariant.t.sol` runs a handler through random
sequences of submit/cancel/settle/NAV-update/time-warp calls and checks, after
every call, that the market's token balances exactly equal what's still owed to
open orders — computed structurally from order state, not from a parallel
ghost-accounting mirror that could hide the same bug twice. It caught a real bug
during development: settling a round by summing each order's own
`floor(price*qty/1e18)` independently can round differently on the buy side than
the sell side even when both sides matched the same total quantity, because
different order-size partitions of the same total round differently. `_settleBuys`
computes each buy order's retained amount once and refunds by subtraction (exact
against its own escrow by construction); `_settleSells` pays every filled order the
standard per-order amount except the last, which absorbs whatever rounding
remainder is left — so the round always settles exactly, never over- or
under-paying. See the NatSpec on `_settleBuys`/`_settleSells` and the deterministic
regression test in `BatchAuctionMarket.t.sol` for the exact numbers.

## Contracts

| Contract | Responsibility |
|---|---|
| `IdentityRegistry` | EAS-backed eligibility cache |
| `PermissionedAssetToken` | ERC-20 tokenized security, transfer-gated on eligibility |
| `NAVOracle` | Issuer-published reference price + staleness bound |
| `CallAuction` (library) | Pure uniform-price clearing algorithm |
| `BatchAuctionMarket` | Order escrow, round lifecycle, settlement, pause |
| `MarketFactory` + `src/factories/*` | Self-serve deployment of a full market set per issuer |

`MarketFactory` orchestrates four small per-contract sub-factories rather than
deploying everything via `new` directly — see its NatSpec for why (EIP-170's
24,576-byte contract size limit).

`IdentityRegistry`, `PermissionedAssetToken`, `NAVOracle`, and `BatchAuctionMarket`
all use `Ownable2Step`, not plain `Ownable`: a bad `transferOwnership` call to an
unreachable address would otherwise strand compliance admin, NAV updates, or
trading entirely, not just convenience. This does not address a single owner key
being compromised — for NAV in particular, that key can set an arbitrary clearing
price — so a multisig or timelock in front of these contracts is the real
production hardening step; this scaffold deliberately leaves that as a deployment
choice rather than baking in one specific governance scheme.

`BatchAuctionMarket` has an issuer-controlled `pause()`/`unpause()` for halts
around distributions or corporate actions (the same real-world reason Theorem's
own product has a pause switch). It only gates new activity — `startRound` and
`submitOrder` — never `cancelOrder` or `settleRound`: a pause must not be able to
trap funds already escrowed in an open round.

## Build & test

```shell
forge build
forge test -vv
```

The `CallAuction` matching algorithm has both example-based and fuzz tests
(`test/CallAuction.t.sol`); `test/BatchAuctionMarket.t.sol` covers a full round
end-to-end, the eligibility edge cases above, pause behavior, a deterministic
rounding regression, and a two-round sequence; `test/invariant/` covers fund
conservation across randomized multi-round sequences (see above).

## Deploy

```shell
cp .env.example .env   # fill in EAS_ADDRESS, SETTLEMENT_TOKEN, PRIVATE_KEY, RPC_URL
forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast --verify
```

Verify `EAS_ADDRESS` (Base's EAS predeploy) and `SETTLEMENT_TOKEN` (native USDC)
against current docs before deploying — see `.env.example`.

## Frontend integration

`abi/` holds one ABI file per contract (regenerate with `./bin/export-abi.sh`
after any contract change), and `config/` holds deployed addresses and
per-market display metadata, both configurable per chain ID and both empty
until the first deployment. See [`INTEGRATION.md`](INTEGRATION.md) for how each
piece of a typical markets/trade UI maps to a contract read, write, or event —
including the one structural point that matters most: Agora has no swap
function, only order submission into a round that settles later.

## Status / roadmap

This is a hackathon-stage scaffold: core matching, escrow, eligibility, and fund
conservation are implemented and tested; NAV is issuer-set rather than pulled from
a live feed; `MarketFactory` deploys full instances rather than minimal proxies;
ownership is `Ownable2Step` but not yet multisig/timelock-gated. Candidate next
steps: a frontend (Base OnchainKit + Smart Wallet for gasless order submission),
an indexer for round history (the per-order `BuyOrderSettled`/`SellOrderSettled`/
`OrderExcludedIneligible` events are meant for this), Clones-based factory
deploys, and an ATS-N-style disclosure tier once a market crosses a volume
threshold.
