# Agora

NAV-anchored adaptive liquidity for tokenized real-world assets.

Agora is a concentrated-liquidity AMM with issuer-defined market controls. Its policy hook provides:

- a NAV-linked trading range;
- dynamic fees around a target price;
- directional rebalancing when the pool moves outside its target zone;
- per-swap limits and stricter NAV freshness for large trades;
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

After publishing NAV, the issuer calls `syncPriceBand` with decimal-aware Q64.96 square-root price bounds. A new NAV invalidates the previous band until this synchronization is complete.

`setRiskControls` configures the target price, directional guard, maximum swap amount, and the tighter freshness requirement for large swaps. `setTemporaryPolicy` applies short-lived bounds and fees that expire without a cleanup transaction.

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
| Agora Demo Note (`ADN`) | [`0x4a72a139e65a25723478e5819F03C2789F40C206`](https://sepolia.basescan.org/address/0x4a72a139e65a25723478e5819F03C2789F40C206) |
| Demo USD (`dUSD`) | [`0xEb9EaC3f9Ec57632CDFDE23D55716c2EA2Fa3a99`](https://sepolia.basescan.org/address/0xEb9EaC3f9Ec57632CDFDE23D55716c2EA2Fa3a99) |
| Identity registry | [`0xcaDF49580A6FF18A10E5fC089E4a1C78DA0151D6`](https://sepolia.basescan.org/address/0xcaDF49580A6FF18A10E5fC089E4a1C78DA0151D6) |
| NAV oracle | [`0xfB8A8746C4f44173b0812cfA1815b8Eb17108B08`](https://sepolia.basescan.org/address/0xfB8A8746C4f44173b0812cfA1815b8Eb17108B08) |
| Allowlist checker | [`0xd2C12D1bd7a925698EAeb66cF781cda1a1E524c9`](https://sepolia.basescan.org/address/0xd2C12D1bd7a925698EAeb66cF781cda1a1E524c9) |
| Pool manager | [`0xb528D4cBB72A86bA7CDbc42100ca24a8283be8E3`](https://sepolia.basescan.org/address/0xb528D4cBB72A86bA7CDbc42100ca24a8283be8E3) |
| Policy hook | [`0xB410db440051eC321Cae11edC322DB6f5AD2a0C0`](https://sepolia.basescan.org/address/0xB410db440051eC321Cae11edC322DB6f5AD2a0C0) |
| Liquidity router | [`0x6B1c7e67A015A7F68d5116239120579FA5bb3236`](https://sepolia.basescan.org/address/0x6B1c7e67A015A7F68d5116239120579FA5bb3236) |
| Swap router | [`0x150f6e746aD2d86D7c6869B29992bfec857bF54D`](https://sepolia.basescan.org/address/0x150f6e746aD2d86D7c6869B29992bfec857bF54D) |

Canonical machine-readable deployment data lives in [`config/markets.json`](config/markets.json).

## Before production

- Replace the demo liquidity and swap routers with production routers.
- Connect frontend quoting and execution to the permissioned router.
- Replace the issuer-managed demo access list with the production identity policy.
- Use a production-grade NAV feed.
