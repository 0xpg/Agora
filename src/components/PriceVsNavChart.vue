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
import { CHART_COLORS } from '@/utils/chartColors'

const props = withDefaults(
  defineProps<{
    navSeries: NavPoint[]
    priceSeries?: NavPoint[]
    compact?: boolean
  }>(),
  { compact: false },
)

const container = ref<HTMLDivElement | null>(null)
const chart = shallowRef<IChartApi | null>(null)
const navLine = shallowRef<ISeriesApi<'Area'> | ISeriesApi<'Line'> | null>(null)
const priceLine = shallowRef<ISeriesApi<'Area'> | null>(null)
let resizeObserver: ResizeObserver | null = null

const tooltip = ref<{ visible: boolean; x: number; y: number; date: string; nav: string; price: string }>({
  visible: false,
  x: 0,
  y: 0,
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

  tooltip.value = {
    visible: true,
    x: param.point.x,
    y: param.point.y,
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
    crosshair: {
      mode: props.compact ? CrosshairMode.Hidden : CrosshairMode.Normal,
    },
    handleScroll: !props.compact,
    handleScale: !props.compact,
  })

  if (props.compact) {
    const area = chart.value.addSeries(AreaSeries, {
      lineColor: CHART_COLORS.primary,
      lineWidth: 2,
      topColor: 'rgba(15, 118, 110, 0.2)',
      bottomColor: 'rgba(15, 118, 110, 0)',
      priceLineVisible: false,
      lastValueVisible: false,
      crosshairMarkerVisible: false,
    })
    area.setData(toChartData(props.navSeries))
    navLine.value = area
  } else {
    // Price: the traded line — solid, with a subtle area fill under it.
    const price = props.priceSeries
      ? chart.value.addSeries(AreaSeries, {
          lineColor: CHART_COLORS.price,
          lineWidth: 2,
          topColor: 'rgba(235, 104, 52, 0.16)',
          bottomColor: 'rgba(235, 104, 52, 0)',
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
    chart.value.applyOptions({ width: entry.contentRect.width, height: entry.contentRect.height })
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
    if (!props.compact) chart.value?.timeScale().fitContent()
  },
)
</script>

<template>
  <div class="relative flex h-full w-full flex-col">
    <div v-if="!compact && priceSeries" class="mb-2 flex items-center gap-4 text-xs text-ink-secondary">
      <span class="inline-flex items-center gap-1.5">
        <span class="h-2 w-2 rounded-full" style="background-color: #eb6834" />
        Price
      </span>
      <span class="inline-flex items-center gap-1.5">
        <span class="h-0.5 w-3 rounded-full border-t-2 border-dashed" style="border-color: #2a78d6" />
        Reference NAV
      </span>
    </div>
    <div ref="container" class="min-h-0 flex-1" />
    <div
      v-if="!compact && tooltip.visible"
      class="pointer-events-none absolute z-10 rounded-md border border-hairline bg-surface px-2.5 py-1.5 text-xs shadow-lg"
      :style="{ left: `${tooltip.x + 12}px`, top: `${tooltip.y + 12}px` }"
    >
      <div class="font-medium text-ink">{{ tooltip.date }}</div>
      <div class="mt-0.5 text-ink-secondary">Price <span class="font-medium tabular-nums text-ink">${{ tooltip.price }}</span></div>
      <div class="text-ink-secondary">NAV <span class="font-medium tabular-nums text-ink">${{ tooltip.nav }}</span></div>
    </div>
  </div>
</template>
