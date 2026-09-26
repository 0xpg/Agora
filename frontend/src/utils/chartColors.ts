// Mirrors the theme tokens in src/assets/main.css. Kept as literal hex here
// because the canvas-based chart library cannot consume CSS custom properties.
export const CHART_COLORS = {
  surface: '#0b110f',
  hairline: '#1a2521',
  axis: '#2b3a35',
  inkMuted: '#6b8079',
  nav: '#60a5fa',
  price: '#fb923c',
  primary: '#10b981',
} as const

// Area fills under each series, as rgba because the library gradients take a
// colour string rather than a token.
export const CHART_FILLS = {
  primaryTop: 'rgba(16, 185, 129, 0.24)',
  primaryBottom: 'rgba(16, 185, 129, 0)',
  priceTop: 'rgba(251, 146, 60, 0.18)',
  priceBottom: 'rgba(251, 146, 60, 0)',
} as const
