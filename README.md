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

Agora is instead a **periodic batch auction**: orders escrow into a round, the
round closes on a timer, and settlement runs once, after close, using only
information that existed before anyone could react to it. There is no
stale-price window to extract, and no LPs required.

The clearing price is deliberately not "whatever price the marginal trader
happened to bid." After matching buys against sells by price, `CallAuction`
looks at the next order on each side that did *not* get matched. If the
midpoint of those two next-in-line prices falls between the last matched buy
and sell price, every matched order clears at that single midpoint — the price
is set entirely by orders that never trade, so no included trader's own bid
moves what they pay. When that midpoint falls outside the matched range
instead, the smallest (marginal) fill is dropped from the match, and the
remaining buyers pay the excluded marginal buy price while the remaining
sellers receive the excluded marginal sell price — two different prices, with
the difference collected as `accumulatedSpread` on `BatchAuctionMarket`,
withdrawable by the issuer. Either way, the price is fixed by someone outside
the final trading set, not by a participant's own order — see
[`src/libraries/CallAuction.sol`](src/libraries/CallAuction.sol).

The NAV band still applies on top of this: the issuer's band is checked
against the midpoint of whatever price(s) result, and the round voids
entirely — a full, untouched refund for every order, nothing partially
matched — if that midpoint sits outside it.

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
`PermissionedAssetToken.exemptOperators`, which exempts `BatchAuctionMarket`
from the eligibility check on both sides of a transfer so escrow and refunds
always move freely between the market and an investor's own wallet.

## Fund conservation

`test/invariant/BatchAuctionMarket.invariant.t.sol` runs a handler through random
sequences of submit/cancel/settle/NAV-update/time-warp/spread-withdrawal calls
and checks, after every call, that the market's token balances always cover
what's still owed to open orders — computed structurally from order state, not
from a parallel ghost-accounting mirror that could hide the same bug twice.

It caught two real bugs during development. First: an early version applied the
NAV-band void check *after* the matching loop had already mutated order
quantities in memory, so a voided round could still hand out tokens without
proper payment — `CallAuction.clear` now works on scratch copies of remaining
quantities and only writes them back to the caller's arrays once every check has
passed (`test_VoidedRoundLeavesOrderQuantitiesUntouched`). Second: an
exact-distribution scheme that forced one side's payouts to sum precisely to a
target pool turned out to risk underflowing a buyer's own refund in rare
many-tiny-orders cases — replaced with independent per-order computation
(provably bounded against that buyer's own escrow) plus a floor-protected
`accumulatedSpread` tracker that only ever understates, never overstates, what's
safely withdrawable.

## Attracting liquidity to a new listing

A fair clearing mechanism does not by itself get anyone to show up: a newly
listed, thin market has no reason to expect a counterparty on the other side of
any given round, and an empty book is a stable outcome, not a bug. `BatchAuctionMarket`
now supports an optional, issuer-configured designated-maker program
(`setMakerProgram`) to bridge that gap: an appointed maker who posts a
qualifying two-sided quote — both a bid and an ask, within the issuer's NAV
band and within a maximum spread — in a given round earns a flat rebate drawn
from `accumulatedSpread`, regardless of whether their quote is ever filled.
The rebate rewards presence, not execution, the same way exchange-run
designated-market-maker programs work.

The subsidy is bounded and self-terminating, not a standing entitlement:
every round, the market counts how many non-maker orders exist on each side.
Once that "organic" two-sided participation threshold is met for enough
consecutive rounds (`graduationRounds`), the program deactivates itself
permanently — no further rebates, no further quoting expectation — on the
theory that a market real participants are already making two-sided doesn't
need a subsidized quoter anymore. The organic count is a count of orders, not
of distinct holders; a rigorous unique-participant count would need its own
tracked set and was left out as unnecessary complexity for what the counter is
protecting (an automatic off-switch, not a precise liquidity metric).

## Contracts

| Contract | Responsibility |
|---|---|
| `IdentityRegistry` | EAS-backed eligibility cache |
| `PermissionedAssetToken` | ERC-20 tokenized security, transfer-gated on eligibility |
| `NAVOracle` | Issuer-published reference price + staleness bound |
| `CallAuction` (library) | Pure clearing algorithm: single or two-sided price, NAV-band gated |
| `BatchAuctionMarket` | Order escrow, round lifecycle, settlement, pause |
| `MarketFactory` + `src/factories/*` | Self-serve deployment of a full market set per issuer |

`MarketFactory` orchestrates four small per-contract sub-factories rather than
deploying everything via `new` directly: embedding all four contracts' creation
bytecode in one contract blows past EIP-170's 24,576-byte runtime size limit
(this contract alone hit ~35KB before the split), and `new X()` inside a
constructor embeds `X`'s bytecode into the caller regardless of how many
indirection layers deep — so the sub-factories are deployed independently (see
`script/Deploy.s.sol`) and `MarketFactory` only ever calls them by address.

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
(`test/CallAuction.t.sol`), including both pricing branches and the
voided-round mutation-safety check; `test/BatchAuctionMarket.t.sol` covers a
full round end-to-end, the eligibility edge cases above, pause behavior, and
spread accumulation/withdrawal; `test/invariant/` covers fund conservation
across randomized multi-round sequences (see above).

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
