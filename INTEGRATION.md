# Frontend integration

Agora is not an AMM. There is no swap function and no instant execution. Trading
is: submit a limit order into whichever round is currently open, wait for that
round's close time, then anyone calls `settleRound()` and every order in it
clears. A Trade page built as a literal "enter amount, click swap" widget has
nothing to call on this contract — it needs to be an order ticket (amount +
limit price, submitted into the open round) with a round countdown and a
pending/settled order state, not an instant result.

A settled round usually has one clearing price for everyone, but not always:
`RoundSettled(roundId, buyPrice, sellPrice, matchedQty)` can carry two different
prices, with the difference retained by the contract as `accumulatedSpread`. A
UI showing "last price" should show both when they differ, not just one.

Everything else — asset factsheet fields, NAV, premium, eligibility, liquidity,
price history — maps directly onto what's below.

## What's here

- `abi/*.json` — one file per contract, just the ABI array, ready for wagmi/viem.
  Regenerate after any contract change with `./bin/export-abi.sh`.
- `config/addresses.json` — deployed addresses per chain ID. All null until the
  first testnet deployment; fill in as markets go live. `markets[]` holds one
  entry per deployed market: `{ id, token, market, navOracle, identityRegistry }`.
- `config/markets.json` — per-market display metadata that has no on-chain home
  (category tag, pool type label, logo, short description). Keyed the same way,
  by chain ID then a `markets[]` array of `{ id, ...display fields }`, joined to
  `addresses.json` by `id`. Edit freely; it's presentation only.

## Markets page

| UI element | Source |
|---|---|
| Asset ticker, category, logo | `config/markets.json` |
| NAV-managed / Standard pool badge | `config/markets.json` |
| KYC badge | presence of required schemas on that market's `IdentityRegistry` |
| Reference NAV | `NAVOracle.getNAV()` |
| Last clearing price(s) ("pool price") | latest `RoundSettled` event for that market — `buyPrice`/`sellPrice`, equal when the round cleared at a single price |
| Premium (bps) | `(midpoint(buyPrice, sellPrice) - nav) / nav`, computed client-side |
| Liquidity | sum of currently-escrowed amounts; cheapest from indexed `OrderSubmitted` minus `OrderCancelled`/settlement events, not a single contract read |
| Price chart | `RoundSettled` history as a step series, clearing price(s) vs NAV |
| 30D volume, total liquidity across markets | aggregate over indexed events across all markets |
| "5 of 6 open" | per market, whether `currentRoundSettled()` is false and `block.timestamp < roundCloseAt()` |
| "Bootstrapping liquidity" badge | `makerProgram()` — `active == true` means a designated maker is currently subsidized on this market; show it as a temporary state, not a permanent liquidity guarantee |

Liquidity and volume aren't single contract reads — pulling them live by
replaying every order for every market on each page load doesn't scale. Stand up
the `ponder.sh` indexer from the README once this matters; for a hackathon demo,
polling `RoundSettled`/`OrderSubmitted` events directly with viem is fine.

## Trade page

| UI element | Source |
|---|---|
| Reference NAV | `NAVOracle.getNAV()` |
| Last clearing price, premium, chart | same as Markets page |
| Issuer | `config/markets.json` |
| Yield, yield mechanism | `config/markets.json` — not modeled on-chain |
| Primary redemption fee | `config/markets.json`, or read from the token if the issuer's mint/burn path charges one (Agora's `PermissionedAssetToken` doesn't by default) |
| Liquidity | same as Markets page |
| Eligibility label | whether `IdentityRegistry.isEligible(connectedAddress)` is true; the label text itself ("Institutional Investor") is `config/markets.json`, not derivable on-chain |
| "NEXT EVENT" halt scheduling | not implemented — `BatchAuctionMarket.pause()` is immediate and issuer-triggered, not a scheduled calendar window. Skip this element or build it as pure frontend copy until a scheduled-pause feature exists |
| The order ticket itself | `BatchAuctionMarket.submitOrder(isBuy, price, qty)`, gated by `IdentityRegistry.isEligible`. Show `roundCloseAt()` as a countdown. After it closes, the order is pending until someone calls `settleRound()` (frontend can call it directly, permissionless) |
| Order result | read the order back via `orders(orderId)` — `settled == true` means resolved; compare `qty` before/after or read the `BuyOrderSettled`/`SellOrderSettled` event for exact filled/refund amounts |
| Cancel | `BatchAuctionMarket.cancelOrder(orderId)`, only before `roundCloseAt()` |
| Designated-maker rebate history | `MakerRebatePaid(roundId, maker, amount)` events; `MakerProgramGraduated(roundId)` marks when the subsidy turned itself off |

## Wiring it up

Standard wagmi/viem setup: import the ABI from `abi/`, the address from
`config/addresses.json` for the connected chain, and go. `MarketFactory.deployMarket`
returns a full new market set in one transaction if the frontend ever needs to
let an issuer self-serve a new listing. The deployed token stays owned by the
factory until the issuer separately calls `PermissionedAssetToken.acceptOwnership()`
— a self-serve listing flow needs to prompt for that as a second step, not assume
ownership transferred in the same transaction.
