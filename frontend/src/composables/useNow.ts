import { onScopeDispose, readonly, ref } from 'vue'
import { nowSeconds } from '@/utils/quote'

/**
 * A ticking clock in unix seconds. Pool policy is time-dependent — NAV ages out
 * of its freshness limit and temporary issuer policies expire on their own — so
 * anything quoting against it has to re-read the time rather than sampling it
 * once at setup.
 */
export function useNow(intervalMs = 1000) {
  const now = ref(nowSeconds())
  const timer = setInterval(() => {
    now.value = nowSeconds()
  }, intervalMs)
  onScopeDispose(() => clearInterval(timer))
  return readonly(now)
}
