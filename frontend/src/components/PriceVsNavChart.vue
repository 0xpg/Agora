<script setup lang="ts">
import { onMounted, onBeforeUnmount, ref, shallowRef, watch } from 'vue'
import {
  createChart,
  AreaSeries,
  LineSeries,
  ColorType,
  CrosshairMode,
  LineStyle,
  LineType,
  type IChartApi,
  type ISeriesApi,
  type MouseEventParams,
  type UTCTimestamp,
} from 'lightweight-charts'
import type { NavPoint } from '@/types/market'
import { CHART_COLORS, CHART_FILLS } from '@/utils/chartColors'

const props = withDefaults(
  defineProps<{
    navSeries: NavPoint[]
    priceSeries?: NavPoint[]
    compact?: boolean
    /* Gives a compact sparkline the same hover readout the full chart has. Off
       by default: the smallest sparklines (the ones in the markets table) are
       barely taller than the chip would be, and their row already spells the
       numbers out in its own columns. */
    hoverReadout?: boolean
  }>(),
  { compact: false, hoverReadout: false },
)

const container = ref<HTMLDivElement | null>(null)
const chart = shallowRef<IChartApi | null>(null)
const navLine = shallowRef<ISeriesApi<'Area'> | ISeriesApi<'Line'> | null>(null)
const priceLine = shallowRef<ISeriesApi<'Area'> | null>(null)
const readout = ref<HTMLElement | null>(null)
let resizeObserver: ResizeObserver | null = null
const box = { width: 0, height: 0 }

const tooltip = ref<{
  visible: boolean
  x: number
  y: number
  /* Compact only: the chip sits at whichever edge the hovered point is not
     near, so it never lands on top of the line it is reporting. */
  below: boolean
  date: string
  nav: string
  price: string
}>({
  visible: false,
  x: 0,
  y: 0,
  below: false,
  date: '',
  nav: '',
  price: '',
})

function toChartData(points: NavPoint[]) {
  return points.map((point) => ({ time: point.time as UTCTimestamp, value: point.value }))
}

function seriesValue(data: unknown): number | undefined {
  if (data && typeof data === 'object' && 'value' in data && typeof data.value === 'number') {
    return data.value
  }
  return undefined
}

function handleCrosshairMove(param: MouseEventParams) {
  if (!param.time || !param.point || !navLine.value) {
    tooltip.value.visible = false
    return
  }
  const navValue = seriesValue(param.seriesData.get(navLine.value))
  const priceValue = priceLine.value ? seriesValue(param.seriesData.get(priceLine.value)) : undefined

  // A compact chip is centred on the cursor, so it has to be held far enough
  // from either edge to stay inside the chart. Its own width is read where it
  // is already on screen, and only guessed on the first move of a hover.
  let x: number = param.point.x
  if (props.compact && box.width) {
    const half = (readout.value?.offsetWidth ?? 92) / 2 + 2
    x = Math.min(Math.max(x, half), box.width - half)
  }

  tooltip.value = {
    visible: true,
    x,
    y: param.point.y,
    below: param.point.y < box.height / 2,
    date: new Date((param.time as number) * 1000).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    }),
    nav: navValue !== undefined ? navValue.toFixed(2) : '',
    price: priceValue !== undefined ? priceValue.toFixed(2) : '',
  }
}

function buildChart() {
  if (!container.value) return

  chart.value = createChart(container.value, {
    layout: {
      background: { type: ColorType.Solid, color: CHART_COLORS.surface },
      textColor: CHART_COLORS.inkMuted,
      fontFamily: 'system-ui, -apple-system, "Segoe UI", sans-serif',
      // Keep the required TradingView attribution on the full chart; a compact
      // sparkline is too small for the logo to render as anything but a smudge.
      attributionLogo: !props.compact,
    },
    grid: {
      vertLines: { visible: false },
      horzLines: { color: CHART_COLORS.hairline },
    },
    rightPriceScale: {
      visible: !props.compact,
      borderColor: CHART_COLORS.hairline,
    },
    timeScale: {
      visible: !props.compact,
      borderColor: CHART_COLORS.hairline,
    },
    crosshair: props.compact
      ? {
          mode: props.hoverReadout ? CrosshairMode.Magnet : CrosshairMode.Hidden,
          vertLine: { color: CHART_COLORS.axis, width: 1, style: LineStyle.Dotted, labelVisible: false },
          horzLine: { visible: false, labelVisible: false },
        }
      : { mode: CrosshairMode.Normal },
    handleScroll: !props.compact,
    handleScale: !props.compact,
  })

  if (props.compact) {
    const area = chart.value.addSeries(AreaSeries, {
      lineColor: CHART_COLORS.primary,
      lineWidth: 2,
      topColor: CHART_FILLS.primaryTop,
      bottomColor: CHART_FILLS.primaryBottom,
      priceLineVisible: false,
      lastValueVisible: false,
      crosshairMarkerVisible: props.hoverReadout,
      crosshairMarkerRadius: 3,
      crosshairMarkerBorderColor: CHART_COLORS.surface,
    })
    area.setData(toChartData(props.navSeries))
    navLine.value = area

    // A sparkline is meant to show the whole series it was handed. Without
    // this it keeps the library's default bar spacing, which on 180 points
    // leaves most of the history off the left of the box.
    chart.value.timeScale().fitContent()
    if (props.hoverReadout) chart.value.subscribeCrosshairMove(handleCrosshairMove)
  } else {
    // Price: the traded line — solid, with a subtle area fill under it.
    const price = props.priceSeries
      ? chart.value.addSeries(AreaSeries, {
          lineColor: CHART_COLORS.price,
          lineWidth: 2,
          topColor: CHART_FILLS.priceTop,
          bottomColor: CHART_FILLS.priceBottom,
          title: 'Price',
        })
      : null
    if (price && props.priceSeries) {
      price.setData(toChartData(props.priceSeries))
      priceLine.value = price
    }

    // Reference NAV: a dashed step line — it's a periodically-marked reference
    // value, not a continuously-traded price, so it reads differently on purpose.
    const nav = chart.value.addSeries(LineSeries, {
      color: CHART_COLORS.nav,
      lineWidth: 2,
      lineStyle: LineStyle.Dashed,
      lineType: LineType.WithSteps,
      title: 'NAV',
    })
    nav.setData(toChartData(props.navSeries))
    navLine.value = nav

    chart.value.timeScale().fitContent()
    chart.value.subscribeCrosshairMove(handleCrosshairMove)
  }

  resizeObserver = new ResizeObserver((entries) => {
    const entry = entries[0]
    if (!entry || !chart.value) return
    box.width = entry.contentRect.width
    box.height = entry.contentRect.height
    chart.value.applyOptions({ width: box.width, height: box.height })
  })
  resizeObserver.observe(container.value)
}

onMounted(buildChart)

onBeforeUnmount(() => {
  resizeObserver?.disconnect()
  chart.value?.remove()
})

watch(
  () => [props.navSeries, props.priceSeries],
  () => {
    if (navLine.value) navLine.value.setData(toChartData(props.navSeries))
    if (priceLine.value && props.priceSeries) priceLine.value.setData(toChartData(props.priceSeries))
    chart.value?.timeScale().fitContent()
  },
)
</script>

<template>
  <div class="relative flex h-full w-full flex-col">
    <div v-if="!compact && priceSeries" class="mb-2 flex items-center gap-4 text-xs text-ink-secondary">
      <span class="inline-flex items-center gap-1.5">
        <span class="h-2 w-2 rounded-full" :style="{ backgroundColor: CHART_COLORS.price }" />
        Price
      </span>
      <span class="inline-flex items-center gap-1.5">
        <span class="h-0.5 w-3 rounded-full border-t-2 border-dashed" :style="{ borderColor: CHART_COLORS.nav }" />
        Reference NAV
      </span>
    </div>
    <div ref="container" class="min-h-0 flex-1" />
    <!-- Sparkline readout: one line, pinned to the edge away from the point.
         The series is unlabelled on purpose — a compact chart is handed a
         single series and the caller decides whether it is price or NAV. -->
    <div
      v-if="compact && hoverReadout && tooltip.visible"
      ref="readout"
      class="pointer-events-none absolute z-10 -translate-x-1/2 whitespace-nowrap rounded border border-hairline bg-elevated px-1.5 py-0.5 text-[10px] leading-tight shadow-lg shadow-black/60"
      :style="tooltip.below ? { left: `${tooltip.x}px`, bottom: '0px' } : { left: `${tooltip.x}px`, top: '0px' }"
    >
      <span class="text-ink-muted">{{ tooltip.date }}</span>
      <span class="ml-1.5 font-medium tabular-nums text-ink">${{ tooltip.nav }}</span>
    </div>

    <div
      v-if="!compact && tooltip.visible"
      class="pointer-events-none absolute z-10 rounded-md border border-hairline bg-elevated px-2.5 py-1.5 text-xs shadow-xl shadow-black/60"
      :style="{ left: `${tooltip.x + 12}px`, top: `${tooltip.y + 12}px` }"
    >
      <div class="font-medium text-ink">{{ tooltip.date }}</div>
      <div class="mt-0.5 text-ink-secondary">Price <span class="font-medium tabular-nums text-ink">${{ tooltip.price }}</span></div>
      <div class="text-ink-secondary">NAV <span class="font-medium tabular-nums text-ink">${{ tooltip.nav }}</span></div>
    </div>
  </div>
</template>
