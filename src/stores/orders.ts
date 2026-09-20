import { defineStore } from 'pinia'
import { ref, onScopeDispose } from 'vue'
import type { BatchOrder, OrderSide, TokenizedAsset } from '@/types/market'
import { getAssetById } from '@/data/mockAssets'

function mulberry32(seed: number) {
  let a = seed
  return () => {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function hashSeed(input: string): number {
  let hash = 0
  for (let i = 0; i < input.length; i++) {
    hash = (Math.imul(31, hash) + input.charCodeAt(i)) | 0
  }
  return hash
}

const REFUND_DELAY_SECONDS = 3

// Orders clear against the round's uniform reference price (the asset's
// current lastPrice, standing in for the batch's clearing price): a buy
// matches if its limit is at least that price, a sell if its limit is at
// most that price. This is a simplified, deterministic stand-in for real
// batch-auction clearing — not a random outcome.
function resolveOrder(order: BatchOrder, asset: TokenizedAsset, now: number) {
  const matches = order.side === 'buy' ? order.limitPrice >= asset.lastPrice : order.limitPrice <= asset.lastPrice

  if (!matches) {
    order.status = 'unmatched'
    order.filledUnits = 0
    order.refundAmount = order.units * order.limitPrice
    order.unmatchedAt = now
    return
  }

  const rand = mulberry32(hashSeed(order.id))
  const isPartial = rand() < 0.4
  if (isPartial) {
    const fillFraction = 0.3 + rand() * 0.6
    order.filledUnits = Math.max(1, Math.round(order.units * fillFraction))
    order.status = 'partially_filled'
    order.refundAmount = (order.units - order.filledUnits) * order.limitPrice
  } else {
    order.filledUnits = order.units
    order.status = 'settled'
    order.refundAmount = 0
  }
}

export const useOrdersStore = defineStore('orders', () => {
  const orders = ref<BatchOrder[]>([])
  const now = ref(Math.floor(Date.now() / 1000))

  const timer = setInterval(() => {
    now.value = Math.floor(Date.now() / 1000)

    for (const order of orders.value) {
      if (order.status === 'pending' && now.value >= order.roundClosesAt) {
        const asset = getAssetById(order.assetId)
        if (asset) resolveOrder(order, asset, now.value)
      } else if (order.status === 'unmatched' && order.unmatchedAt && now.value - order.unmatchedAt >= REFUND_DELAY_SECONDS) {
        order.status = 'refunded'
      }
    }
  }, 1000)

  onScopeDispose(() => clearInterval(timer))

  function submitOrder(asset: TokenizedAsset, side: OrderSide, units: number, limitPrice: number): BatchOrder {
    const order: BatchOrder = {
      id: crypto.randomUUID(),
      assetId: asset.id,
      side,
      units,
      limitPrice,
      status: 'pending',
      createdAt: now.value,
      roundClosesAt: asset.roundClosesAt,
      filledUnits: 0,
      refundAmount: 0,
    }
    orders.value.push(order)
    return order
  }

  function cancelOrder(id: string) {
    const order = orders.value.find((o) => o.id === id)
    if (!order || order.status !== 'pending') return
    order.status = 'cancelled'
    order.refundAmount = order.units * order.limitPrice
  }

  function orderForAsset(assetId: string): BatchOrder | undefined {
    const forAsset = orders.value.filter((o) => o.assetId === assetId)
    return forAsset[forAsset.length - 1]
  }

  return { orders, now, submitOrder, cancelOrder, orderForAsset }
})
