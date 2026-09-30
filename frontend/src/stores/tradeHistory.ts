import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { TARGET_CHAIN_ID } from '@/config/chain'

/**
 * A record of every trade this browser attempted, kept per wallet.
 *
 * It is written here rather than read back from the chain because a reverted or
 * rejected transaction emits no events — a failed attempt is invisible to any
 * log query, and those are exactly the attempts an investor most needs to see
 * again. Every entry describes a real transaction this wallet signed or
 * declined; nothing is synthesised.
 *
 * The consequence is that it is per-device: trades made in another browser will
 * not appear. The portfolio says so rather than implying the list is complete.
 */
export type TradeStatus = 'confirmed' | 'reverted' | 'rejected' | 'failed'

export interface TradeRecord {
  id: string
  /** Lower-cased address that made the attempt. */
  wallet: string
  chainId: number
  assetId: string
  symbol: string
  settlementSymbol: string
  side: 'buy' | 'sell'
  mode: 'exactIn' | 'exactOut'
  /** What was paid and received, in display units. */
  amountIn: number
  amountOut: number
  executionPrice: number
  feeBps: number
  feeAmount: number
  priceImpactPct: number
  /** Null when the attempt never reached the chain. */
  hash: string | null
  status: TradeStatus
  /** Why it did not complete, for anything but a confirmed trade. */
  reason?: string
  /** Unix seconds — the block's time when confirmed, otherwise when it was attempted. */
  timestamp: number
}

const STORAGE_KEY = 'agora.trade-history.v1'
/** Enough to be useful, bounded so the entry never grows without limit. */
const MAX_PER_WALLET = 50

type Stored = Record<string, TradeRecord[]>

function load(): Stored {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return {}
    const parsed: unknown = JSON.parse(raw)
    return parsed && typeof parsed === 'object' ? (parsed as Stored) : {}
  } catch {
    // Private windows, blocked site data, or a corrupted entry. History is a
    // convenience; losing it must never stop the app from working.
    return {}
  }
}

function save(value: Stored) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(value))
  } catch {
    // Quota or blocked storage — the in-memory list still serves this session.
  }
}

export const useTradeHistoryStore = defineStore('tradeHistory', () => {
  const all = ref<Stored>(load())
  const wallet = ref<string | null>(null)

  function key(address: string): string {
    return `${TARGET_CHAIN_ID}:${address.toLowerCase()}`
  }

  const records = computed<TradeRecord[]>(() => {
    if (!wallet.value) return []
    return all.value[key(wallet.value)] ?? []
  })

  const hasAny = computed(() => records.value.length > 0)

  function setWallet(address: string | null) {
    wallet.value = address
  }

  function record(entry: Omit<TradeRecord, 'id' | 'wallet' | 'chainId'>) {
    if (!wallet.value) return
    const full: TradeRecord = {
      ...entry,
      id: `${entry.hash ?? 'local'}-${entry.timestamp}-${Math.random().toString(36).slice(2, 8)}`,
      wallet: wallet.value.toLowerCase(),
      chainId: TARGET_CHAIN_ID,
    }
    const bucket = key(wallet.value)
    const next = { ...all.value, [bucket]: [full, ...(all.value[bucket] ?? [])].slice(0, MAX_PER_WALLET) }
    all.value = next
    save(next)
  }

  function clear() {
    if (!wallet.value) return
    const next = { ...all.value }
    delete next[key(wallet.value)]
    all.value = next
    save(next)
  }

  return { records, hasAny, setWallet, record, clear }
})
