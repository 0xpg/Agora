import type { TokenizedAsset } from '@/types/market'

export function premiumDiscountPct(asset: TokenizedAsset): number {
  return ((asset.lastPrice - asset.nav) / asset.nav) * 100
}
