<script setup lang="ts">
import { computed } from 'vue'
import { ELIGIBILITY_TIER_LABEL, type MarketRules, type EligibilityTier } from '@/types/market'
import AssetInfoRows, { type InfoRow } from '@/components/AssetInfoRows.vue'

const props = defineProps<{
  rules: MarketRules
  requiredTiers: EligibilityTier[]
}>()

const rows = computed<InfoRow[]>(() => [
  { label: 'Eligible Investor Tiers', value: props.requiredTiers.map((t) => ELIGIBILITY_TIER_LABEL[t]).join(', ') },
  { label: 'Trading Window', value: props.rules.tradingWindow },
  { label: 'Lock-up Period', value: `${props.rules.lockupPeriodDays} days from issuance` },
  { label: 'Minimum Holding Period', value: `${props.rules.minHoldingPeriodDays} days` },
  { label: 'Maximum Ownership', value: `${props.rules.maxOwnershipPct}% of total supply per investor` },
  { label: 'Transfer Restrictions', value: props.rules.transferRestrictions, span: 'full' },
])
</script>

<template>
  <AssetInfoRows title="Issuer-Defined Market Rules" :rows="rows" />
</template>
