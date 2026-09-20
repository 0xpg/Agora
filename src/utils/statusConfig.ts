import type { MarketStatus, OrderStatus, RoundStatus } from '@/types/market'
import type { EligibilityState } from '@/composables/useEligibility'

export interface StatusVisual {
  label: string
  dot: string
  text: string
}

export const MARKET_STATUS_CONFIG: Record<MarketStatus, StatusVisual> = {
  open: { label: 'Open for Trading', dot: 'bg-good', text: 'text-success' },
  restricted: { label: 'Restricted', dot: 'bg-critical', text: 'text-critical' },
  paused: { label: 'Paused (NAV Update)', dot: 'bg-warning', text: 'text-ink-secondary' },
}

export const ELIGIBILITY_CONFIG: Record<EligibilityState, StatusVisual> = {
  eligible: { label: 'Eligible', dot: 'bg-good', text: 'text-success' },
  kyc_pending: { label: 'KYC Pending', dot: 'bg-warning', text: 'text-ink-secondary' },
  restricted: { label: 'Restricted', dot: 'bg-critical', text: 'text-critical' },
}

export const ROUND_STATUS_CONFIG: Record<RoundStatus, StatusVisual> = {
  open: { label: 'Round Open', dot: 'bg-primary', text: 'text-primary-ink' },
  settling: { label: 'Settling', dot: 'bg-warning', text: 'text-ink-secondary' },
  closed: { label: 'Round Closed', dot: 'bg-ink-muted', text: 'text-ink-muted' },
}

export const ORDER_STATUS_CONFIG: Record<OrderStatus, StatusVisual> = {
  pending: { label: 'Pending', dot: 'bg-primary', text: 'text-primary-ink' },
  partially_filled: { label: 'Partially Filled', dot: 'bg-warning', text: 'text-ink-secondary' },
  unmatched: { label: 'Unmatched', dot: 'bg-ink-muted', text: 'text-ink-muted' },
  cancelled: { label: 'Cancelled', dot: 'bg-ink-muted', text: 'text-ink-muted' },
  refunded: { label: 'Refunded', dot: 'bg-good', text: 'text-success' },
  settled: { label: 'Settled', dot: 'bg-good', text: 'text-success' },
}
