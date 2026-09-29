# Changelog

## Unreleased

- Scaffold Foundry contracts: IdentityRegistry, PermissionedAssetToken, NAVOracle, CallAuction, BatchAuctionMarket, MarketFactory
- CI workflow (forge fmt, build, test) on push and pull request
- Optional issuer-configured designated-maker program on `BatchAuctionMarket`: a flat, spread-funded rebate for a qualifying two-sided quote each round, self-terminating once organic two-sided order flow sustains for enough consecutive rounds
- `IEligibilityOracle` interface extracted from `IdentityRegistry`; `BatchAuctionMarket` now depends on the interface, not the concrete contract
