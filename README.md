# Agora

NAV-anchored adaptive liquidity for secondary markets in tokenized real-world assets.

Agora is a concentrated-liquidity AMM with issuer-defined market controls. Its policy hook provides:

- a NAV-linked trading range;
- dynamic fees based on NAV deviation, one-sided inventory flow, and short-term price movement;
- directional rebalancing when the pool moves outside its target zone;
- per-swap and cumulative epoch limits that prevent split-trade bypasses;
- delayed, jump-limited NAV updates;
- issuer pause controls; and
- temporary emergency parameters with automatic expiry.

## Architecture

```text
Privy wallet -> swap router -> singleton pool manager -> policy hook
```

| Component | Responsibility |
|---|---|
| `AgoraHook` | Price bounds, dynamic fees, risk limits, and emergency controls |
| `NAVOracle` | Issuer-published NAV and freshness policy |
| `PermissionedAssetToken` | Token issuance and transfer restrictions |
| `IdentityRegistry` | Issuer-managed demo access list for Privy wallets |
| `MarketFactory` | Deploys the contracts for a new market |
| Privy | Wallet and email onboarding |

Privy handles onboarding. For the hackathon demo, wallets self-register on-chain and can mint demo settlement tokens during their first trade; external identity attestations are intentionally out of scope.

## Market controls

The initial NAV is published directly. Later values use `scheduleNAV` and `activateNAV`; the issuer configures the activation delay and maximum permitted change with `setUpdatePolicy`. Every activated NAV invalidates the old price band until the issuer calls `syncPriceBand` with decimal-aware Q64.96 square-root price bounds.

`setRiskControls` configures the target price, directional guard, maximum swap amount, and tighter freshness requirement for large swaps. `setFlowRisk` adds gross and directional net-flow budgets per epoch. Trades that worsen accumulated inventory imbalance pay an additional fee, while rebalancing trades do not. A bounded movement fee responds to the price change since the previous swap. `setTemporaryPolicy` applies short-lived bounds and fees that expire without a cleanup transaction.

`SwapRiskEvaluated` exposes the fee components, NAV timestamp, and current epoch utilization. `FlowRecorded` records the actual asset amount after settlement; limits therefore apply to executed output rather than user-supplied quote data.

Issuer ownership should be transferred to a Safe before production use.

## Development

```shell
git clone --recurse-submodules https://github.com/0xpg/Agora.git
cd Agora
forge build
forge test -vv
```

For an existing clone:

```shell
git submodule update --init --recursive
```

CI runs `forge fmt --check`, `forge build --sizes`, and `forge test -vvv`.

The Vue frontend uses Privy for wallet onboarding. Agora Demo Note executes against the deployed Base Sepolia swap router; the other showcase markets use representative data.

## Base Sepolia deployment

| Contract | Address |
|---|---|
| Agora Demo Note (`ADN`) | [`0x6985ae688BcCeB88D00aaf07e3bFB49e6BFfa1e6`](https://sepolia.basescan.org/address/0x6985ae688BcCeB88D00aaf07e3bFB49e6BFfa1e6) |
| Demo USD (`dUSD`) | [`0x28d1ed434444653FEa153c3d0d412464ed9B6d1D`](https://sepolia.basescan.org/address/0x28d1ed434444653FEa153c3d0d412464ed9B6d1D) |
| Demo identity registry | [`0x0b77a93455FBb2Ab67235bc139e266ab71661a24`](https://sepolia.basescan.org/address/0x0b77a93455FBb2Ab67235bc139e266ab71661a24) |
| NAV oracle | [`0x67b65bBfe0c02C7e6bf72470b4f550CefDD3254A`](https://sepolia.basescan.org/address/0x67b65bBfe0c02C7e6bf72470b4f550CefDD3254A) |
| Demo allowlist checker | [`0x73c1A20dba8d10AC80aFd640120ccdD8C7b30a92`](https://sepolia.basescan.org/address/0x73c1A20dba8d10AC80aFd640120ccdD8C7b30a92) |
| Pool manager | [`0xBdd5c751AED5c22ef3CcEDC59d63F67c15f886d8`](https://sepolia.basescan.org/address/0xBdd5c751AED5c22ef3CcEDC59d63F67c15f886d8) |
| Policy hook | [`0x674AF11220306Fd24A5a2fAc42FB1f4DfF5A20C0`](https://sepolia.basescan.org/address/0x674AF11220306Fd24A5a2fAc42FB1f4DfF5A20C0) |
| Liquidity router | [`0x640AAc21F4715bBeAdc45628e1273467B299CdDb`](https://sepolia.basescan.org/address/0x640AAc21F4715bBeAdc45628e1273467B299CdDb) |
| Swap router | [`0xE57FDf474472D9e1e5c9A1d32F31CcfeB98732EC`](https://sepolia.basescan.org/address/0xE57FDf474472D9e1e5c9A1d32F31CcfeB98732EC) |

Canonical machine-readable deployment data lives in [`config/markets.json`](config/markets.json).

The deployed source is published through Sourcify. A successful end-to-end ADN swap is recorded in [BaseScan transaction `0xea1517…75c34`](https://sepolia.basescan.org/tx/0xea1517f3c9aad4851b2e750a18f129440a29970f1c233dd66ba821a335075c34), including the pool `Swap` and token `Transfer` events. Reproduce it with `script/SmokeSwap.s.sol`.

## Before production

- Replace the demo liquidity and swap routers with production routers.
- Connect frontend quoting and execution to the permissioned router.
- Replace the issuer-managed demo access list with the production identity policy.
- Use a production-grade NAV feed.
