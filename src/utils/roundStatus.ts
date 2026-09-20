import type { RoundStatus, TokenizedAsset } from '@/types/market'

const SETTLING_WINDOW_SECONDS = 5

export function roundStatusFor(asset: TokenizedAsset, now: number): RoundStatus {
  if (asset.marketStatus !== 'open') return 'closed'
  const secondsUntilClose = asset.roundClosesAt - now
  if (secondsUntilClose > 0) return 'open'
  if (secondsUntilClose > -SETTLING_WINDOW_SECONDS) return 'settling'
  return 'closed'
}

export function formatCountdown(seconds: number): string {
  if (seconds <= 0) return '0s'
  const m = Math.floor(seconds / 60)
  const s = seconds % 60
  return m > 0 ? `${m}m ${s}s` : `${s}s`
}
