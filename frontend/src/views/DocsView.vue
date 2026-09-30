<script setup lang="ts">
import type { PoolCondition } from '@/utils/quote'
import { POOL_CONDITION_CONFIG } from '@/utils/statusConfig'

const SECTIONS = [
  { id: 'how-trading-works', title: 'How trading works' },
  { id: 'price-and-nav', title: 'Price, NAV and the permitted range' },
  { id: 'fees-and-impact', title: 'Fees, price impact and slippage' },
  { id: 'amounts', title: 'Exact input and exact output' },
  { id: 'limits', title: 'Trade limits and NAV freshness' },
  { id: 'pool-states', title: 'When a pool will not trade' },
  { id: 'getting-started', title: 'Getting started' },
] as const

// Drawn from the same table the status badges use, so the docs cannot drift from
// what the app actually shows.
const POOL_STATES: { condition: PoolCondition; meaning: string }[] = [
  {
    condition: 'open',
    meaning: 'Both directions trade. Quotes settle as soon as you confirm them.',
  },
  {
    condition: 'rebalance_only',
    meaning:
      'Price has moved far enough from NAV that the pool accepts only swaps bringing it back. The other direction is refused until price returns toward NAV.',
  },
  {
    condition: 'nav_update',
    meaning:
      'Either the published NAV has aged past its freshness limit, or a new NAV has been published and the issuer has not yet re-anchored the price range to it. Trading resumes once the next NAV is in place.',
  },
  {
    condition: 'outside_band',
    meaning:
      'Pool price has left the range the issuer permits. Every swap is refused until liquidity brings price back inside it.',
  },
  {
    condition: 'paused',
    meaning: 'The issuer has paused the pool. Nothing is required from you; swaps reopen when they unpause it.',
  },
]
</script>

<template>
  <div class="mx-auto max-w-6xl px-6 py-8">
    <div class="mb-8 flex flex-col gap-1">
      <h1 class="text-xl font-semibold text-ink">Docs</h1>
      <p class="text-sm text-ink-muted">How trading works on Agora.</p>
    </div>

    <div class="grid grid-cols-1 gap-8 lg:grid-cols-[1fr_15rem]">
      <div class="min-w-0 space-y-4">
        <section class="rounded-lg border border-hairline bg-surface p-6">
          <p class="text-sm leading-relaxed text-ink-secondary">
            Agora is a secondary market for tokenized real-world assets. Each asset trades against its own liquidity
            pool, with liquidity concentrated around the asset's net asset value and a policy the issuer sets and the
            pool enforces on every swap. Trading is continuous: there are no sessions to wait for and no orders to
            place. You review a quote and confirm it, and it settles.
          </p>
        </section>

        <section id="how-trading-works" class="scroll-mt-20 rounded-lg border border-hairline bg-surface p-6">
          <h2 class="text-sm font-semibold text-ink">How trading works</h2>
          <p class="mt-2 text-sm leading-relaxed text-ink-secondary">
            You trade against the pool, not against another investor. The pool always holds both the asset and the
            market's settlement currency, and it prices a swap by moving along a curve between the two. Buying moves
            the price up; selling moves it down. Because you are trading against inventory rather than waiting for a
            counterparty, the size you can trade at once is set by how much of that inventory sits within the
            permitted price range — which is what a quote's price impact is telling you.
          </p>
        </section>

        <section id="price-and-nav" class="scroll-mt-20 rounded-lg border border-hairline bg-surface p-6">
          <h2 class="text-sm font-semibold text-ink">Price, NAV and the permitted range</h2>
          <p class="mt-2 text-sm leading-relaxed text-ink-secondary">
            Two prices matter on every market. <span class="text-ink">Pool price</span> is what the pool will trade at
            right now. <span class="text-ink">Reference NAV</span> is the value the issuer publishes for the asset
            itself. The gap between them is the premium or discount, and it is shown in basis points on every asset.
          </p>
          <p class="mt-3 text-sm leading-relaxed text-ink-secondary">
            Around NAV the issuer sets a permitted price range. The pool refuses any swap that would start outside that
            range or land outside it — so instead of filling you at a price the issuer considers unreasonable, the
            transaction does not go through. Each market's trade page draws this range, with NAV, the live pool price,
            and where your quoted trade would leave it.
          </p>
        </section>

        <section id="fees-and-impact" class="scroll-mt-20 rounded-lg border border-hairline bg-surface p-6">
          <h2 class="text-sm font-semibold text-ink">Fees, price impact and slippage</h2>
          <p class="mt-2 text-sm leading-relaxed text-ink-secondary">
            The fee is not fixed. It is lowest when pool price sits at NAV and rises the further price has moved from
            it, reaching its maximum at the edge of the permitted range. Trading a pool back toward NAV is therefore
            cheaper than pushing it further away. Every quote shows the rate it was priced at, in basis points.
          </p>
          <p class="mt-3 text-sm leading-relaxed text-ink-secondary">
            Three costs are reported separately, because they are three different things:
          </p>
          <dl class="mt-3 space-y-2.5 text-sm">
            <div>
              <dt class="font-medium text-ink">Pool fee</dt>
              <dd class="text-ink-secondary">What the pool charges for the swap, set by distance from NAV.</dd>
            </div>
            <div>
              <dt class="font-medium text-ink">Price impact</dt>
              <dd class="text-ink-secondary">
                How far your own trade moves the price along the curve. It grows with size, and it is the reason a
                large trade gets a worse average price than a small one.
              </dd>
            </div>
            <div>
              <dt class="font-medium text-ink">Slippage tolerance</dt>
              <dd class="text-ink-secondary">
                Your own limit on being re-priced between quoting and confirming. The pool can move in that window —
                another swap, a new NAV — and past your tolerance the swap reverts rather than settling worse than you
                accepted.
              </dd>
            </div>
          </dl>
        </section>

        <section id="amounts" class="scroll-mt-20 rounded-lg border border-hairline bg-surface p-6">
          <h2 class="text-sm font-semibold text-ink">Exact input and exact output</h2>
          <p class="mt-2 text-sm leading-relaxed text-ink-secondary">
            You can specify either leg of a swap. Type into
            <span class="text-ink">You pay</span> and you have set an exact input: you spend precisely that amount, and
            the quote shows the minimum you will receive for it. Type into
            <span class="text-ink">You receive</span> and you have set an exact output: you get precisely that amount,
            and the quote shows the maximum you will pay to get it.
          </p>
          <p class="mt-3 text-sm leading-relaxed text-ink-secondary">
            Both are subject to the same policy. Whichever leg you fix, the other is what the slippage bound applies
            to.
          </p>
        </section>

        <section id="limits" class="scroll-mt-20 rounded-lg border border-hairline bg-surface p-6">
          <h2 class="text-sm font-semibold text-ink">Trade limits and NAV freshness</h2>
          <p class="mt-2 text-sm leading-relaxed text-ink-secondary">
            Issuers cap the size of a single swap. A trade above the cap is refused rather than partly filled, so
            larger size has to be split across several swaps. Each market's pool policy shows its own cap.
          </p>
          <p class="mt-3 text-sm leading-relaxed text-ink-secondary">
            Pricing depends on a published NAV, so that NAV has to be recent. Every pool has a freshness limit, and
            past it all trading stops until the issuer publishes a new one. Larger trades are usually held to a
            tighter limit than ordinary ones — a trade that would be accepted at a small size can be refused at a
            large one purely because NAV is not new enough for it.
          </p>
        </section>

        <section id="pool-states" class="scroll-mt-20 rounded-lg border border-hairline bg-surface p-6">
          <h2 class="text-sm font-semibold text-ink">When a pool will not trade</h2>
          <p class="mt-2 text-sm leading-relaxed text-ink-secondary">
            A pool's condition is shown on its market listing and at the top of its trade page. These are the states
            you may see, and what each one means for you.
          </p>
          <dl class="mt-4 space-y-3">
            <div
              v-for="state in POOL_STATES"
              :key="state.condition"
              class="border-t border-hairline pt-3 first:border-t-0 first:pt-0"
            >
              <dt class="flex items-center gap-1.5 text-sm font-medium" :class="POOL_CONDITION_CONFIG[state.condition].text">
                <span class="h-1.5 w-1.5 rounded-full" :class="POOL_CONDITION_CONFIG[state.condition].dot" />
                {{ POOL_CONDITION_CONFIG[state.condition].label }}
              </dt>
              <dd class="mt-1 text-sm leading-relaxed text-ink-secondary">{{ state.meaning }}</dd>
            </div>
          </dl>
          <p class="mt-4 border-t border-hairline pt-3 text-sm leading-relaxed text-ink-secondary">
            Separately, an issuer may apply a temporary policy — a short-lived price range and fee curve for an
            unusual day. It is labelled wherever it is in force and expires on its own.
          </p>
        </section>

        <section id="getting-started" class="scroll-mt-20 rounded-lg border border-hairline bg-surface p-6">
          <h2 class="text-sm font-semibold text-ink">Getting started</h2>
          <p class="mt-2 text-sm leading-relaxed text-ink-secondary">
            Sign in with an email address or connect an existing wallet. Signing in with email creates a wallet for you
            in the background, so you do not need one beforehand; either way, the wallet you end up with is the one
            that holds your assets and signs your swaps.
          </p>
          <p class="mt-3 text-sm leading-relaxed text-ink-secondary">
            Each asset states the investor tier and verification it requires, and the trade page tells you where you
            stand against those requirements before you enter an amount.
          </p>
        </section>
      </div>

      <nav aria-label="On this page" class="order-first lg:order-none">
        <div class="lg:sticky lg:top-20">
          <p class="text-[11px] font-medium tracking-wide text-ink-muted uppercase">On this page</p>
          <ul class="mt-2 space-y-1.5">
            <li v-for="section in SECTIONS" :key="section.id">
              <a :href="`#${section.id}`" class="block text-sm text-ink-secondary transition hover:text-primary">
                {{ section.title }}
              </a>
            </li>
          </ul>
        </div>
      </nav>
    </div>
  </div>
</template>
