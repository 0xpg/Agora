<script setup lang="ts">
import { computed, type Directive } from 'vue'
import { RouterLink } from 'vue-router'
import { mockAssets } from '@/data/mockAssets'
import { mockInvestor } from '@/data/mockInvestor'
import { TARGET_CHAIN_NAME } from '@/config/chain'
import { premiumDiscountPct } from '@/utils/pricing'
import { formatBps, formatCurrency, formatPercent } from '@/utils/format'
import AssetCard from '@/components/AssetCard.vue'
import LandingGlobe from '@/components/LandingGlobe.vue'
import SummaryMetrics, { type MetricItem } from '@/components/SummaryMetrics.vue'

const VALUE_PROPS = [
  {
    title: 'Discover',
    body: 'Browse tokenized real-world assets across real estate, credit, treasuries, and more — filtered by class, issuer, and eligibility.',
  },
  {
    title: 'Verified Access',
    body: "Every asset lists the investor tier and KYC status it requires, so you know upfront whether you're eligible to trade it.",
  },
  {
    title: 'Transparent NAV',
    body: "See how each asset's market price compares to its reference NAV, with full price history alongside it.",
  },
  {
    title: 'Batch-Auction Settlement',
    body: 'Orders enter a timed round and settle against a fair, uniform clearing price once it closes — this is not an instant swap.',
  },
] as const

const HOW_IT_WORKS = [
  {
    title: 'Discover a market',
    body: 'Browse tokenized assets by class, issuer, or eligibility, and see each one’s live NAV and pricing context.',
  },
  {
    title: 'Confirm eligibility',
    body: 'Every asset lists its required investor tier and KYC status, so you always know where you stand before trading.',
  },
  {
    title: 'Submit an order into a round',
    body: 'Place a buy or sell order with a limit price. It enters the current batch auction round instead of executing immediately.',
  },
  {
    title: 'Get your settlement or refund',
    body: "Once the round closes, your order settles, partially fills, or is refunded — you'll see the result and any funds returned.",
  },
] as const

const FOOTER_LINKS = [
  { to: '/markets', label: 'Markets' },
  { to: '/trade', label: 'Trade' },
  { to: '/portfolio', label: 'Portfolio' },
  { to: '/docs', label: 'Docs' },
] as const

const HEADLINE_WORDS = ['Real-world', 'assets,', 'made', 'discoverable', 'and'] as const

// A mix of open markets, not filtered to only what this particular investor is
// eligible for — an anonymous visitor hasn't connected a wallet yet, and seeing
// a restricted card here doubles as a preview of the "Verified Access" idea.
const previewAssets = computed(() =>
  [...mockAssets]
    .filter((asset) => asset.marketStatus === 'open')
    .sort((a, b) => b.liquidity - a.liquidity)
    .slice(0, 3),
)

const previewMetrics = computed<MetricItem[]>(() => {
  const totalLiquidity = mockAssets.reduce((sum, asset) => sum + asset.liquidity, 0)
  const avgPremiumPct =
    mockAssets.reduce((sum, asset) => sum + premiumDiscountPct(asset), 0) / mockAssets.length
  return [
    { label: 'TOTAL LIQUIDITY', value: formatCurrency(totalLiquidity, 'USD', 0) },
    {
      label: 'AVG. PREMIUM TO NAV',
      value: formatBps(avgPremiumPct),
      valueClass: avgPremiumPct >= 0 ? 'text-success' : 'text-critical',
    },
    { label: 'ASSETS LISTED', value: String(mockAssets.length) },
  ]
})

// The ticker scrolls one continuous strip, so the list is rendered twice and
// translated by exactly half its width — the seam lands where the copy begins.
const tickerAssets = computed(() =>
  mockAssets.map((asset) => ({
    id: asset.id,
    symbol: asset.symbol,
    premium: premiumDiscountPct(asset),
  })),
)

const reducedMotion =
  typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches

// Reveal-on-scroll. A directive rather than component state because it is purely
// presentational and needs the element itself; the binding value is a stagger
// delay in milliseconds. Each element is observed once and released on entry.
const observers = new WeakMap<HTMLElement, IntersectionObserver>()
const vReveal: Directive<HTMLElement, number | undefined> = {
  mounted(el, binding) {
    if (reducedMotion) return
    el.classList.add('reveal')
    if (binding.value) el.style.setProperty('--reveal-delay', `${binding.value}ms`)
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue
          entry.target.classList.add('is-visible')
          observer.unobserve(entry.target)
        }
      },
      { threshold: 0.15, rootMargin: '0px 0px -8% 0px' },
    )
    observer.observe(el)
    observers.set(el, observer)
  },
  unmounted(el) {
    observers.get(el)?.disconnect()
    observers.delete(el)
  },
}

// Feeds the card's spotlight gradient the cursor position. Pointer-driven only,
// so it costs nothing on touch devices where the gradient never shows.
function trackPointer(event: PointerEvent) {
  const el = event.currentTarget as HTMLElement
  const rect = el.getBoundingClientRect()
  el.style.setProperty('--mx', `${event.clientX - rect.left}px`)
  el.style.setProperty('--my', `${event.clientY - rect.top}px`)
}
</script>

<template>
  <div class="relative isolate overflow-hidden bg-page">
    <!-- Ambient backdrop: the turning globe, over its own halo. Purely
         decorative, so it sits behind everything and ignores the pointer. -->
    <div class="pointer-events-none absolute inset-x-0 top-0 -z-10 h-[920px] overflow-hidden" aria-hidden="true">
      <div class="halo" />
      <div class="globe-stage">
        <LandingGlobe />
      </div>
      <div class="globe-scrim" />
    </div>

    <header class="sticky top-0 z-50 border-b border-hairline bg-page/70 backdrop-blur-md">
      <div class="mx-auto flex max-w-6xl items-center justify-between gap-4 px-6 py-4">
        <RouterLink to="/" class="group flex items-center gap-2">
          <span
            class="flex h-5 w-5 rotate-45 rounded-[3px] bg-primary shadow-[0_0_18px_var(--color-primary)] transition-transform duration-500 group-hover:rotate-[135deg]"
          />
          <span class="text-base font-semibold tracking-tight text-ink">Agora</span>
        </RouterLink>
        <div class="flex items-center gap-4">
          <a href="#how-it-works" class="hidden text-sm font-medium text-ink-secondary transition hover:text-primary sm:inline">
            How it works
          </a>
          <RouterLink to="/markets" class="cta-primary text-sm">Enter Agora</RouterLink>
        </div>
      </div>
    </header>

    <section class="mx-auto max-w-5xl px-6 pt-20 pb-14 text-center sm:pt-28">
      <div class="hero-rise inline-flex items-center gap-2 rounded-full border border-hairline bg-surface/70 px-3 py-1 text-xs text-ink-secondary backdrop-blur">
        <span class="relative flex h-1.5 w-1.5">
          <span class="pulse-ring absolute inline-flex h-full w-full rounded-full bg-primary" />
          <span class="relative inline-flex h-1.5 w-1.5 rounded-full bg-primary" />
        </span>
        Batch-auction RWA exchange &middot; {{ TARGET_CHAIN_NAME }}
      </div>

      <h1 class="mt-6 text-4xl font-semibold tracking-tight text-ink sm:text-6xl">
        <span
          v-for="(word, index) in HEADLINE_WORDS"
          :key="word"
          class="hero-rise mr-[0.25em] inline-block"
          :style="{ '--reveal-delay': `${80 + index * 70}ms` }"
        >
          {{ word }}
        </span>
        <span class="hero-rise shimmer inline-block" :style="{ '--reveal-delay': `${80 + HEADLINE_WORDS.length * 70}ms` }">
          tradable.
        </span>
      </h1>

      <p class="hero-rise mx-auto mt-6 max-w-2xl text-lg text-ink-secondary" style="--reveal-delay: 500ms">
        Explore tokenized assets, understand their value, and participate in transparent market rounds&mdash;all in one
        place.
      </p>

      <div class="hero-rise mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row" style="--reveal-delay: 600ms">
        <RouterLink to="/markets" class="cta-primary text-sm">Enter Agora</RouterLink>
        <a
          href="#how-it-works"
          class="rounded-full border border-hairline px-6 py-3 text-sm font-semibold text-ink transition hover:border-primary/60 hover:text-primary"
        >
          How it works
        </a>
      </div>
    </section>

    <!-- Live-feeling ticker of every listed market, premium to NAV alongside. -->
    <div class="hero-rise relative border-y border-hairline bg-surface/40 py-3" style="--reveal-delay: 700ms">
      <div class="ticker-mask">
        <div class="ticker flex w-max items-center">
          <span
            v-for="(entry, index) in [...tickerAssets, ...tickerAssets]"
            :key="`${entry.id}-${index}`"
            class="flex items-center gap-2 px-5 text-xs"
          >
            <span class="font-semibold tracking-wide text-ink">{{ entry.symbol }}</span>
            <span class="tabular-nums" :class="entry.premium >= 0 ? 'text-success' : 'text-critical'">
              {{ formatPercent(entry.premium) }}
            </span>
            <span class="text-hairline">|</span>
          </span>
        </div>
      </div>
    </div>

    <section class="mx-auto max-w-6xl px-6 py-20">
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <div
          v-for="(item, index) in VALUE_PROPS"
          v-reveal="index * 90"
          :key="item.title"
          class="spotlight group rounded-xl border border-hairline bg-surface p-6 transition-colors duration-300 hover:border-primary/40"
          @pointermove="trackPointer"
        >
          <span class="text-xs font-medium tabular-nums text-primary">{{ String(index + 1).padStart(2, '0') }}</span>
          <h3 class="mt-3 text-sm font-semibold text-ink">{{ item.title }}</h3>
          <p class="mt-1.5 text-sm text-ink-secondary">{{ item.body }}</p>
        </div>
      </div>
    </section>

    <section class="mx-auto max-w-6xl px-6 pb-20">
      <div v-reveal class="mb-8 text-center">
        <h2 class="text-2xl font-semibold text-ink sm:text-3xl">A glimpse of the markets</h2>
        <p class="mt-2 text-sm text-ink-secondary">
          Real assets, real batch-auction rounds &mdash; this is what you'll see inside.
        </p>
      </div>
      <SummaryMetrics v-reveal="80" :metrics="previewMetrics" class="mb-6" />
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <div v-for="(asset, index) in previewAssets" v-reveal="160 + index * 90" :key="asset.id" class="lift">
          <AssetCard :asset="asset" :investor="mockInvestor" />
        </div>
      </div>
      <div v-reveal="420" class="mt-8 text-center">
        <RouterLink to="/markets" class="arrow-link text-sm font-semibold text-primary">
          See all markets <span class="arrow inline-block">&rarr;</span>
        </RouterLink>
      </div>
    </section>

    <section id="how-it-works" class="mx-auto max-w-4xl scroll-mt-20 px-6 py-20">
      <h2 v-reveal class="text-2xl font-semibold text-ink sm:text-3xl">How it works</h2>
      <ol class="relative mt-10 space-y-9">
        <!-- The rail behind the step markers, drawn top-down as it scrolls in. -->
        <span v-reveal class="rail absolute top-2 bottom-2 left-4 w-px bg-gradient-to-b from-primary/60 via-primary/25 to-transparent" aria-hidden="true" />
        <li v-for="(step, index) in HOW_IT_WORKS" v-reveal="index * 110" :key="step.title" class="relative flex gap-5">
          <span
            class="z-10 flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-primary/40 bg-primary-soft text-sm font-semibold tabular-nums text-primary-ink shadow-[0_0_20px_-4px_var(--color-primary)]"
          >
            {{ index + 1 }}
          </span>
          <div>
            <h3 class="text-sm font-semibold text-ink">{{ step.title }}</h3>
            <p class="mt-1 text-sm text-ink-secondary">{{ step.body }}</p>
          </div>
        </li>
      </ol>
      <p v-reveal class="mt-10 rounded-lg border border-warning/30 bg-warning/5 px-4 py-3 text-xs text-ink-secondary">
        Some parts of this flow &mdash; like live wallet connections and on-chain settlement &mdash; are still being
        finalized. What you see today runs on representative data while the underlying integration comes together.
      </p>
    </section>

    <section class="mx-auto max-w-4xl px-6 pb-24">
      <div
        v-reveal
        class="spotlight relative overflow-hidden rounded-2xl border border-primary/25 bg-surface px-8 py-12 text-center"
        @pointermove="trackPointer"
      >
        <h2 class="text-2xl font-semibold text-ink sm:text-3xl">Start with the markets.</h2>
        <p class="mx-auto mt-3 max-w-md text-sm text-ink-secondary">
          No wallet needed to look around — connect only when you're ready to place an order into a round.
        </p>
        <RouterLink to="/markets" class="cta-primary mt-7 inline-flex text-sm">Enter Agora</RouterLink>
      </div>
    </section>

    <footer class="border-t border-hairline">
      <div
        class="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 px-6 py-8 text-xs text-ink-muted sm:flex-row"
      >
        <span>&copy; 2026 Agora.</span>
        <nav class="flex flex-wrap items-center justify-center gap-4">
          <RouterLink v-for="link in FOOTER_LINKS" :key="link.to" :to="link.to" class="transition hover:text-primary">
            {{ link.label }}
          </RouterLink>
        </nav>
      </div>
    </footer>
  </div>
</template>

<style scoped>
/* Shared entry transition. Elements are laid out normally and only offset
   visually, so nothing reflows when they settle. */
.reveal,
.hero-rise {
  opacity: 0;
  transform: translateY(14px);
}

.reveal.is-visible,
.hero-rise {
  transition:
    opacity 0.7s cubic-bezier(0.16, 1, 0.3, 1) var(--reveal-delay, 0ms),
    transform 0.7s cubic-bezier(0.16, 1, 0.3, 1) var(--reveal-delay, 0ms);
}

.reveal.is-visible {
  opacity: 1;
  transform: none;
}

.rail.is-visible {
  animation: rail-draw 1s cubic-bezier(0.16, 1, 0.3, 1) var(--reveal-delay, 0ms) backwards;
}

/* The accent button: emerald fill, ambient glow, and a highlight that sweeps
   across on hover. */
.cta-primary {
  position: relative;
  overflow: hidden;
  border-radius: 9999px;
  background-color: var(--color-primary);
  padding: 0.75rem 1.5rem;
  font-weight: 600;
  color: var(--color-on-accent);
  box-shadow: 0 0 0 0 color-mix(in oklab, var(--color-primary) 60%, transparent);
  transition:
    box-shadow 0.35s ease,
    transform 0.35s ease,
    background-color 0.35s ease;
}

.cta-primary:hover {
  background-color: color-mix(in oklab, var(--color-primary) 88%, white);
  box-shadow: 0 0 28px -4px color-mix(in oklab, var(--color-primary) 70%, transparent);
  transform: translateY(-1px);
}

.cta-primary::after {
  content: '';
  position: absolute;
  inset: 0;
  transform: translateX(-120%);
  background: linear-gradient(100deg, transparent 20%, rgb(255 255 255 / 0.35) 50%, transparent 80%);
}

.cta-primary:hover::after {
  transform: translateX(120%);
  transition: transform 0.7s ease;
}

/* Cursor-tracked glow. --mx/--my are written by the pointermove handler. */
.spotlight {
  position: relative;
}

.spotlight::before {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: inherit;
  opacity: 0;
  transition: opacity 0.35s ease;
  background: radial-gradient(
    18rem circle at var(--mx, 50%) var(--my, 50%),
    color-mix(in oklab, var(--color-primary) 14%, transparent),
    transparent 70%
  );
}

.spotlight:hover::before {
  opacity: 1;
}

.spotlight > * {
  position: relative;
}

.lift {
  transition: transform 0.35s cubic-bezier(0.16, 1, 0.3, 1);
}

.lift:hover {
  transform: translateY(-4px);
}

.arrow {
  transition: transform 0.3s ease;
}

.arrow-link:hover .arrow {
  transform: translateX(4px);
}

/* Ambient background layers: the globe and the glow it sits in. */
.globe-stage {
  position: absolute;
  top: -6%;
  left: 50%;
  aspect-ratio: 1;
  width: min(1060px, 148vw);
  transform: translateX(-50%);
  opacity: 0.62;
  /* The lattice runs at full strength right up to the edge of the sphere, so
     the rim is softened rather than cut, and the foot is faded out before it
     reaches the ticker. */
  mask-image:
    radial-gradient(circle at 50% 50%, black 54%, transparent 73%),
    linear-gradient(to bottom, black 56%, transparent 94%);
  mask-composite: intersect;
}

/* Sits between the globe and the copy: the middle of the sphere is dimmed back
   towards the page colour so the headline has something quiet to sit on, while
   the limb stays bright. Without it the dots read straight through the text. */
.globe-scrim {
  position: absolute;
  inset: 0;
  background: radial-gradient(
    ellipse 44% 30% at 50% 30%,
    var(--color-page) 0%,
    color-mix(in oklab, var(--color-page) 72%, transparent) 48%,
    transparent 76%
  );
}

.halo {
  position: absolute;
  top: -12rem;
  left: 50%;
  height: 40rem;
  width: 52rem;
  margin-left: -26rem;
  border-radius: 9999px;
  opacity: 0.45;
  filter: blur(100px);
  background: radial-gradient(circle, color-mix(in oklab, var(--color-primary) 40%, transparent), transparent 70%);
}

.ticker-mask {
  overflow: hidden;
  mask-image: linear-gradient(to right, transparent, black 8%, black 92%, transparent);
}

@media (prefers-reduced-motion: no-preference) {
  .hero-rise {
    animation: rise 0.8s cubic-bezier(0.16, 1, 0.3, 1) var(--reveal-delay, 0ms) backwards;
    opacity: 1;
    transform: none;
  }

  .halo {
    animation: drift 20s ease-in-out infinite alternate;
  }

  .pulse-ring {
    animation: pulse-ring 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
  }

  /* Half of the strip is a duplicate, so -50% lands exactly on the repeat. */
  .ticker {
    animation: marquee 45s linear infinite;
  }

  .ticker:hover {
    animation-play-state: paused;
  }

  .shimmer {
    background: linear-gradient(
      100deg,
      var(--color-primary) 20%,
      color-mix(in oklab, var(--color-primary) 40%, var(--color-ink)) 45%,
      var(--color-primary) 70%
    );
    background-size: 220% 100%;
    background-clip: text;
    color: transparent;
    animation:
      rise 0.8s cubic-bezier(0.16, 1, 0.3, 1) var(--reveal-delay, 0ms) backwards,
      shimmer 6s linear infinite 1s;
  }
}

/* Without the animation above, the accent word still needs its colour. */
.shimmer {
  color: var(--color-primary);
}

@media (prefers-reduced-motion: reduce) {
  .hero-rise {
    opacity: 1;
    transform: none;
  }
}

@keyframes rise {
  from {
    opacity: 0;
    transform: translateY(16px);
  }
  to {
    opacity: 1;
    transform: none;
  }
}

@keyframes rail-draw {
  from {
    transform: scaleY(0);
    transform-origin: top;
  }
  to {
    transform: scaleY(1);
    transform-origin: top;
  }
}

@keyframes drift {
  from {
    transform: translate3d(-2rem, 0, 0) scale(1);
  }
  to {
    transform: translate3d(2rem, 1.5rem, 0) scale(1.1);
  }
}

@keyframes pulse-ring {
  0% {
    transform: scale(1);
    opacity: 0.8;
  }
  70%,
  100% {
    transform: scale(2.6);
    opacity: 0;
  }
}

@keyframes marquee {
  from {
    transform: translateX(0);
  }
  to {
    transform: translateX(-50%);
  }
}

@keyframes shimmer {
  from {
    background-position: 200% 0;
  }
  to {
    background-position: -200% 0;
  }
}
</style>
