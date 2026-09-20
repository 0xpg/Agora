<script setup lang="ts">
import { RouterView, useRoute } from 'vue-router'
import AppHeader from '@/components/layout/AppHeader.vue'
import { mockInvestor } from '@/data/mockInvestor'

const route = useRoute()
</script>

<template>
  <div class="min-h-screen bg-page">
    <AppHeader v-if="route.name !== 'landing'" :investor="mockInvestor" />
    <RouterView />
  </div>
</template>
