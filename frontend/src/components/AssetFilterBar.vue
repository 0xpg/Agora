<script setup lang="ts">
import type { AssetClass } from '@/types/market'
import { PERPETUAL } from '@/composables/useAssetFilters'
import { formatMaturity } from '@/utils/format'

defineProps<{
  assetClasses: AssetClass[]
  issuers: string[]
  domiciles: string[]
  currencies: string[]
  maturities: string[]
}>()

const search = defineModel<string>('search', { required: true })
const classFilter = defineModel<AssetClass | 'all'>('classFilter', { required: true })
const onlyEligible = defineModel<boolean>('onlyEligible', { required: true })
const issuerFilter = defineModel<string>('issuerFilter', { required: true })
const domicileFilter = defineModel<string>('domicileFilter', { required: true })
const currencyFilter = defineModel<string>('currencyFilter', { required: true })
const maturityFilter = defineModel<string>('maturityFilter', { required: true })

const selectClass =
  'rounded-md border border-hairline bg-surface px-2.5 py-2 text-xs text-ink-secondary focus:border-primary focus:outline-none'
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center gap-2">
      <input
        v-model="search"
        type="text"
        placeholder="Search ticker, issuer, or underlying asset"
        class="w-full rounded-md border border-hairline bg-surface px-3 py-2 text-sm focus:border-primary focus:outline-none sm:w-auto sm:max-w-xs"
      />
      <select v-model="issuerFilter" :class="selectClass">
        <option value="all">All issuers</option>
        <option v-for="issuer in issuers" :key="issuer" :value="issuer">{{ issuer }}</option>
      </select>
      <select v-model="domicileFilter" :class="selectClass">
        <option value="all">All domiciles</option>
        <option v-for="domicile in domiciles" :key="domicile" :value="domicile">{{ domicile }}</option>
      </select>
      <select v-model="currencyFilter" :class="selectClass">
        <option value="all">All currencies</option>
        <option v-for="currency in currencies" :key="currency" :value="currency">{{ currency }}</option>
      </select>
      <select v-model="maturityFilter" :class="selectClass">
        <option value="all">All maturities</option>
        <option v-for="maturity in maturities" :key="maturity" :value="maturity">
          {{ formatMaturity(maturity === PERPETUAL ? null : maturity) }}
        </option>
      </select>
      <label class="ml-auto flex items-center gap-2 text-sm text-ink-secondary">
        <input v-model="onlyEligible" type="checkbox" class="h-4 w-4 rounded border-hairline" />
        Only show what I'm eligible for
      </label>
    </div>

    <div class="flex flex-wrap gap-2">
      <button
        type="button"
        class="rounded-full border px-3 py-1 text-xs font-medium transition"
        :class="
          classFilter === 'all'
            ? 'border-primary bg-primary text-on-accent'
            : 'border-hairline text-ink-secondary hover:border-ink-muted'
        "
        @click="classFilter = 'all'"
      >
        All
      </button>
      <button
        v-for="cls in assetClasses"
        :key="cls"
        type="button"
        class="rounded-full border px-3 py-1 text-xs font-medium transition"
        :class="
          classFilter === cls
            ? 'border-primary bg-primary text-on-accent'
            : 'border-hairline text-ink-secondary hover:border-ink-muted'
        "
        @click="classFilter = cls"
      >
        {{ cls }}
      </button>
    </div>
  </div>
</template>
