<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { readThemeColor } from '@/utils/themeTokens'

/* A slowly turning globe of dots, with continents picked out of it.
 *
 * The landmasses follow the approach playgrnd.tools uses in "Sonar": value
 * noise, smoothed and stacked, pushed around by a second field, then cut at a
 * single level — the coastline is found rather than drawn, so bays, spits and
 * the odd inland sea fall out of the field on their own. A band either side of
 * the cut breaks up into dither, which is what keeps the coast from reading as
 * a clean vector edge.
 *
 * The noise is sampled in 3D at the sphere point itself rather than on a
 * lon/lat rectangle. A flat field would have to wrap at the seam and would
 * pinch at the poles; sampled in 3D it does neither.
 */

/* The lattice puts roughly 150 dots across the diameter, so a hemisphere reads
 * about 150 map columns — 384 around the full sphere is already more detail
 * than the dots can show. */
const MAP_W = 384
const MAP_H = 192
const SEED = 1207

/* Spacing of the dot lattice in CSS pixels, and the size of a dot within it. */
const CELL = 7
const DOT = 2

/* Limb shading is quantised so a frame draws as a handful of batched fills
 * rather than a few thousand individual state changes. */
const SHADES = 6

/* Tilted a little off upright, so the pole sits where a globe's does. */
const TILT = -0.38
const SPIN_PER_MS = 0.000085

const canvas = ref<HTMLCanvasElement | null>(null)

function hash3(x: number, y: number, z: number, s: number): number {
  let n = Math.imul(x | 0, 374761393) ^ Math.imul(y | 0, 668265263) ^ Math.imul(z | 0, 1440662683) ^ Math.imul(s | 0, 1013904223)
  n = Math.imul(n ^ (n >>> 15), 2246822519)
  n = Math.imul(n ^ (n >>> 13), 3266489917)
  n ^= n >>> 16
  return (n >>> 0) / 4294967296
}

function vnoise3(x: number, y: number, z: number, s: number): number {
  const xi = Math.floor(x)
  const yi = Math.floor(y)
  const zi = Math.floor(z)
  const xf = x - xi
  const yf = y - yi
  const zf = z - zi
  const u = xf * xf * (3 - 2 * xf)
  const v = yf * yf * (3 - 2 * yf)
  const w = zf * zf * (3 - 2 * zf)

  const lerp = (a: number, b: number, t: number) => a + (b - a) * t
  const c00 = lerp(hash3(xi, yi, zi, s), hash3(xi + 1, yi, zi, s), u)
  const c10 = lerp(hash3(xi, yi + 1, zi, s), hash3(xi + 1, yi + 1, zi, s), u)
  const c01 = lerp(hash3(xi, yi, zi + 1, s), hash3(xi + 1, yi, zi + 1, s), u)
  const c11 = lerp(hash3(xi, yi + 1, zi + 1, s), hash3(xi + 1, yi + 1, zi + 1, s), u)
  return lerp(lerp(c00, c10, v), lerp(c01, c11, v), w)
}

function fbm3(x: number, y: number, z: number, s: number, octaves: number): number {
  let value = 0
  let amp = 0.5
  let freq = 1
  let total = 0
  for (let i = 0; i < octaves; i++) {
    value += amp * vnoise3(x * freq, y * freq, z * freq, s + i * 131)
    total += amp
    freq *= 2
    amp *= 0.5
  }
  return value / total
}

/* Baked once: 1 where the cut says land, 0 where it says sea. */
function buildLandMap(): Uint8Array {
  const map = new Uint8Array(MAP_W * MAP_H)
  const scale = 2.15
  const warpAmount = 0.55
  const level = 0.52
  const band = 0.045

  for (let row = 0; row < MAP_H; row++) {
    const lat = (0.5 - (row + 0.5) / MAP_H) * Math.PI
    const cosLat = Math.cos(lat)
    const sinLat = Math.sin(lat)
    for (let col = 0; col < MAP_W; col++) {
      const lon = ((col + 0.5) / MAP_W) * Math.PI * 2
      const px = cosLat * Math.cos(lon) * scale
      const py = sinLat * scale
      const pz = cosLat * Math.sin(lon) * scale

      // The second field is what turns concentric blobs into coastlines.
      const wx = fbm3(px * 0.9 + 19, py * 0.9, pz * 0.9, SEED + 77, 2) - 0.5
      const wy = fbm3(px * 0.9, py * 0.9 + 31, pz * 0.9, SEED + 151, 2) - 0.5

      const field = fbm3(px + wx * warpAmount, py + wy * warpAmount, pz, SEED, 4)

      // Poles bias towards sea, which stops the lattice crowding into a solid
      // cap where the dot rows converge.
      const biased = field - Math.pow(Math.abs(sinLat), 3) * 0.22

      let land: boolean
      if (biased > level + band) land = true
      else if (biased < level - band) land = false
      else {
        // Inside the fringe, how far across decides the odds, and a per-cell
        // draw decides the cell — so the coast dissolves instead of stepping.
        const t = (biased - (level - band)) / (2 * band)
        land = hash3(col, row, 0, SEED + 909) < t
      }
      map[row * MAP_W + col] = land ? 1 : 0
    }
  }
  return map
}

/* Everything about a dot that the spin does not change: where it sits, which
 * map row it reads, its longitude before the spin is added, and how lit it is.
 * Rebuilt only on resize. */
interface Cell {
  x: number
  y: number
  rowOffset: number
  lonFrac: number
  shade: number
}

/* Canvas needs a plain colour string, so the accent is unpacked into channels
 * and alpha applied directly — color-mix() is not reliably accepted as a
 * fillStyle, and a rejected one silently keeps the previous colour. */
function readAccentRgb(): [number, number, number] {
  const hex = readThemeColor('--color-primary', '#10b981').slice(1)
  const full = hex.length === 3 ? hex.replace(/./g, (c) => c + c) : hex
  return [
    parseInt(full.slice(0, 2), 16),
    parseInt(full.slice(2, 4), 16),
    parseInt(full.slice(4, 6), 16),
  ]
}

onMounted(() => {
  const el = canvas.value
  if (!el) return
  const ctx = el.getContext('2d')
  if (!ctx) return

  // Baking the field costs long enough to be felt if it lands before the first
  // paint. The globe is decorative, so it is built once the page is on screen
  // and fades in when it is ready; everything below tolerates it being absent.
  let map: Uint8Array | null = null
  const [r, g, b] = readAccentRgb()

  // Land and sea are the same ink at different strengths, so the sphere reads
  // as one object lit from the front rather than two overlaid patterns.
  const landFills: string[] = []
  const seaFills: string[] = []
  for (let i = 0; i < SHADES; i++) {
    const t = (i + 1) / SHADES
    landFills.push(`rgba(${r},${g},${b},${(0.16 + t * 0.78).toFixed(3)})`)
    seaFills.push(`rgba(${r},${g},${b},${(0.03 + t * 0.13).toFixed(3)})`)
  }

  let cells: Cell[] = []
  let dpr = 1
  const landBuckets: number[][] = Array.from({ length: SHADES }, () => [])
  const seaBuckets: number[][] = Array.from({ length: SHADES }, () => [])

  function layout() {
    const host = el!.parentElement ?? el!
    const width = host.clientWidth
    const height = host.clientHeight
    if (!width || !height) return

    dpr = Math.min(window.devicePixelRatio || 1, 2)
    el!.width = Math.round(width * dpr)
    el!.height = Math.round(height * dpr)
    el!.style.width = `${width}px`
    el!.style.height = `${height}px`

    const cx = width / 2
    const cy = height / 2
    const radius = Math.min(width, height) / 2
    const next: Cell[] = []

    for (let y = cy - radius; y <= cy + radius; y += CELL) {
      for (let x = cx - radius; x <= cx + radius; x += CELL) {
        const nx = (x - cx) / radius
        const ny = (y - cy) / radius
        const d2 = nx * nx + ny * ny
        if (d2 > 1) continue
        const nz = Math.sqrt(1 - d2)

        // Tilt the sphere about the horizontal axis before reading a latitude.
        const ty = ny * Math.cos(TILT) - nz * Math.sin(TILT)
        const tz = ny * Math.sin(TILT) + nz * Math.cos(TILT)

        const lat = Math.asin(Math.max(-1, Math.min(1, -ty)))
        const lon = Math.atan2(nx, tz)

        const row = Math.min(MAP_H - 1, Math.max(0, Math.floor((0.5 - lat / Math.PI) * MAP_H)))
        let lonFrac = lon / (Math.PI * 2)
        lonFrac -= Math.floor(lonFrac)

        // Dots towards the limb sit at a glancing angle, so they dim.
        const shade = Math.min(SHADES - 1, Math.floor(Math.pow(nz, 0.55) * SHADES))

        next.push({ x, y, rowOffset: row * MAP_W, lonFrac, shade })
      }
    }
    cells = next
  }

  function draw(spinFrac: number) {
    if (!map) return
    const width = el!.width / dpr
    const height = el!.height / dpr
    ctx!.setTransform(dpr, 0, 0, dpr, 0, 0)
    ctx!.clearRect(0, 0, width, height)

    for (const bucket of landBuckets) bucket.length = 0
    for (const bucket of seaBuckets) bucket.length = 0

    for (const cell of cells) {
      let u = cell.lonFrac + spinFrac
      u -= Math.floor(u)
      const col = Math.min(MAP_W - 1, (u * MAP_W) | 0)
      const bucket = map![cell.rowOffset + col] ? landBuckets[cell.shade]! : seaBuckets[cell.shade]!
      bucket.push(cell.x, cell.y)
    }

    for (let i = 0; i < SHADES; i++) {
      for (const [fills, buckets] of [
        [seaFills, seaBuckets],
        [landFills, landBuckets],
      ] as const) {
        const points = buckets[i]!
        if (!points.length) continue
        ctx!.fillStyle = fills[i]!
        for (let p = 0; p < points.length; p += 2) {
          ctx!.fillRect(points[p]! - DOT / 2, points[p + 1]! - DOT / 2, DOT, DOT)
        }
      }
    }
  }

  layout()

  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)')
  let frame = 0
  let spin = 0
  let last = 0
  let running = false

  function tick(now: number) {
    spin += (now - last) * SPIN_PER_MS
    last = now
    draw(spin / (Math.PI * 2))
    frame = requestAnimationFrame(tick)
  }

  function start() {
    // A still globe is the whole picture for anyone who asked for less motion,
    // and off-screen or in a hidden tab there is nothing to animate for.
    if (running || !map || reduced.matches || document.hidden) return
    running = true
    last = performance.now()
    frame = requestAnimationFrame(tick)
  }

  function stop() {
    running = false
    cancelAnimationFrame(frame)
  }

  const observer = new IntersectionObserver((entries) => {
    if (entries.some((entry) => entry.isIntersecting)) start()
    else stop()
  })
  observer.observe(el)

  const resizeObserver = new ResizeObserver(() => {
    layout()
    draw(spin / (Math.PI * 2))
  })
  resizeObserver.observe(el.parentElement ?? el)

  function onVisibility() {
    if (document.hidden) stop()
    else start()
  }
  document.addEventListener('visibilitychange', onVisibility)
  reduced.addEventListener('change', () => (reduced.matches ? stop() : start()))

  // Two hops: one frame to let the page paint, then a task so the bake itself
  // is not inside the frame either.
  let bake: number | undefined
  const paintFrame = requestAnimationFrame(() => {
    bake = window.setTimeout(() => {
      map = buildLandMap()
      el!.classList.add('ready')
      draw(0)
      start()
    }, 0)
  })

  onBeforeUnmount(() => {
    stop()
    cancelAnimationFrame(paintFrame)
    if (bake !== undefined) clearTimeout(bake)
    observer.disconnect()
    resizeObserver.disconnect()
    document.removeEventListener('visibilitychange', onVisibility)
  })
})
</script>

<template>
  <canvas ref="canvas" aria-hidden="true" />
</template>

<style scoped>
/* Absent until the field is baked, so it arrives rather than pops. */
canvas {
  opacity: 0;
  transition: opacity 1.2s ease-out;
}

canvas.ready {
  opacity: 1;
}
</style>
