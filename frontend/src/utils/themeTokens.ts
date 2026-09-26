/**
 * The palette lives in CSS custom properties (src/assets/main.css). Anything
 * that has to hand a colour to something which cannot read CSS — a canvas, a
 * third-party SDK — reads it back through here, so the theme stays one
 * definition rather than a set of copies that drift apart.
 */
export function readThemeColor(token: string, fallback: `#${string}`): `#${string}` {
  if (typeof document === 'undefined') return fallback
  const value = getComputedStyle(document.documentElement).getPropertyValue(token).trim()
  return /^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i.test(value) ? (value as `#${string}`) : fallback
}
