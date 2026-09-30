import type { PoolCondition } from '@/utils/quote'
import type { EligibilityState } from '@/composables/useEligibility'

export interface StatusVisual {
  label: string
  dot: string
  text: string
}

export const POOL_CONDITION_CONFIG: Record<PoolCondition, StatusVisual> = {
  open: { label: 'Open for Trading', dot: 'bg-good', text: 'text-success' },
  rebalance_only: { label: 'Rebalancing Only', dot: 'bg-warning', text: 'text-warning' },
  nav_update: { label: 'NAV Update in Progress', dot: 'bg-warning', text: 'text-warning' },
  outside_band: { label: 'Outside NAV Range', dot: 'bg-critical', text: 'text-critical' },
  paused: { label: 'Paused by Issuer', dot: 'bg-serious', text: 'text-serious' },
}

export const ELIGIBILITY_CONFIG: Record<EligibilityState, StatusVisual> = {
  eligible: { label: 'Eligible', dot: 'bg-good', text: 'text-success' },
  kyc_pending: { label: 'KYC Pending', dot: 'bg-warning', text: 'text-ink-secondary' },
  restricted: { label: 'Restricted', dot: 'bg-critical', text: 'text-critical' },
}
