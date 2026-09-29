import type { MarketStatus } from '@/types/market'
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
