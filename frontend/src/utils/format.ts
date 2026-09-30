export function formatCurrency(value: number, currency = 'USD', maximumFractionDigits = 2): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency,
    maximumFractionDigits,
  }).format(value)
}

export function formatCompactNumber(value: number): string {
  return new Intl.NumberFormat('en-US', { notation: 'compact', maximumFractionDigits: 1 }).format(value)
}

export function formatPercent(value: number, maximumFractionDigits = 2): string {
  const sign = value > 0 ? '+' : ''
  return `${sign}${value.toFixed(maximumFractionDigits)}%`
}

// Takes a percentage (e.g. premium/discount to NAV) and renders it in basis points.
export function formatBps(percentValue: number, maximumFractionDigits = 0): string {
  const bps = percentValue * 100
  const sign = bps > 0 ? '+' : ''
  return `${sign}${bps.toFixed(maximumFractionDigits)} bps`
}

// Yields are absolute rates, not deltas — no forced sign, and "no yield" reads as "—".
export function formatRate(value: number | null, maximumFractionDigits = 2): string {
  return value === null ? '—' : `${value.toFixed(maximumFractionDigits)}%`
}

export function formatCompactCurrency(value: number, currency = 'USD'): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency,
    notation: 'compact',
    maximumFractionDigits: 2,
  }).format(value)
}

export function truncateAddress(address: string, lead = 5, trail = 4): string {
  return `${address.slice(0, lead)}...${address.slice(-trail)}`
}

/** A policy window or an age, as the shortest phrase that stays exact. */
export function formatDuration(seconds: number): string {
  if (seconds < 60) return `${Math.max(Math.round(seconds), 0)} sec`
  const minutes = seconds / 60
  if (minutes < 90) return `${Math.round(minutes)} min`
  const hours = minutes / 60
  if (hours < 48) return `${Number(hours.toFixed(hours % 1 === 0 ? 0 : 1))} hr`
  return `${Math.round(hours / 24)} days`
}

export function formatAge(seconds: number): string {
  return `${formatDuration(seconds)} ago`
}

export function formatMaturity(date: string | null): string {
  if (!date) return 'Perpetual'
  return new Date(date).toLocaleDateString('en-US', { year: 'numeric', month: 'short' })
}
