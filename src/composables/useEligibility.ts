import { ELIGIBILITY_TIER_LABEL, type Investor, type TokenizedAsset } from '@/types/market'

export type EligibilityState = 'eligible' | 'kyc_pending' | 'restricted'

export function eligibilityState(asset: TokenizedAsset, investor: Investor): EligibilityState {
  if (!asset.requiredTiers.includes(investor.tier)) return 'restricted'
  if (asset.kycRequired && investor.kycStatus !== 'verified') return 'kyc_pending'
  return 'eligible'
}

export function isEligible(asset: TokenizedAsset, investor: Investor): boolean {
  return eligibilityState(asset, investor) === 'eligible'
}

function requiredTiersLabel(asset: TokenizedAsset): string {
  return asset.requiredTiers.map((tier) => ELIGIBILITY_TIER_LABEL[tier]).join(' or ')
}

export function eligibilityReason(asset: TokenizedAsset, investor: Investor): string {
  const state = eligibilityState(asset, investor)
  if (state === 'eligible') return 'You meet this issuer\'s eligibility requirements.'
  if (state === 'kyc_pending') {
    return 'Your KYC verification must be completed before trading this asset.'
  }
  return `This asset is restricted to ${requiredTiersLabel(asset)} investors. Your current tier is ${ELIGIBILITY_TIER_LABEL[investor.tier]}.`
}

// Short-form reason for tight spaces (asset cards) — same precedence as eligibilityReason.
export function eligibilityReasonShort(asset: TokenizedAsset, investor: Investor): string {
  const state = eligibilityState(asset, investor)
  if (state === 'eligible') return ''
  if (state === 'kyc_pending') return 'Complete KYC to trade'
  return `Restricted to ${requiredTiersLabel(asset)}`
}
