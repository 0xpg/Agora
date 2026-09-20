import { computed, ref } from 'vue'
import type { AssetClass, Investor, TokenizedAsset } from '@/types/market'
import { eligibilityState } from '@/composables/useEligibility'

// Sentinel used for both the "no fixed maturity" option and matching filter value.
export const PERPETUAL = 'perpetual'

function uniqueSorted(values: string[]): string[] {
  return Array.from(new Set(values)).sort()
}

export function useAssetFilters(assets: TokenizedAsset[], investor: Investor) {
  const search = ref('')
  const classFilter = ref<AssetClass | 'all'>('all')
  const onlyEligible = ref(false)
  const issuerFilter = ref<string>('all')
  const domicileFilter = ref<string>('all')
  const currencyFilter = ref<string>('all')
  const maturityFilter = ref<string>('all')

  const assetClasses = computed<AssetClass[]>(() => {
    const set = new Set(assets.map((asset) => asset.assetClass))
    return Array.from(set)
  })
  const issuers = computed(() => uniqueSorted(assets.map((asset) => asset.issuer)))
  const domiciles = computed(() => uniqueSorted(assets.map((asset) => asset.domicile)))
  const currencies = computed(() => uniqueSorted(assets.map((asset) => asset.currency)))
  const maturities = computed(() => uniqueSorted(assets.map((asset) => asset.maturityDate ?? PERPETUAL)))

  const filteredAssets = computed(() => {
    return assets.filter((asset) => {
      if (classFilter.value !== 'all' && asset.assetClass !== classFilter.value) return false
      if (onlyEligible.value && eligibilityState(asset, investor) !== 'eligible') return false
      if (issuerFilter.value !== 'all' && asset.issuer !== issuerFilter.value) return false
      if (domicileFilter.value !== 'all' && asset.domicile !== domicileFilter.value) return false
      if (currencyFilter.value !== 'all' && asset.currency !== currencyFilter.value) return false
      if (maturityFilter.value !== 'all' && (asset.maturityDate ?? PERPETUAL) !== maturityFilter.value) return false
      if (search.value.trim()) {
        const term = search.value.trim().toLowerCase()
        if (!asset.name.toLowerCase().includes(term) && !asset.symbol.toLowerCase().includes(term)) return false
      }
      return true
    })
  })

  return {
    search,
    classFilter,
    onlyEligible,
    issuerFilter,
    domicileFilter,
    currencyFilter,
    maturityFilter,
    assetClasses,
    issuers,
    domiciles,
    currencies,
    maturities,
    filteredAssets,
  }
}
