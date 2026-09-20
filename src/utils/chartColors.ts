// Mirrors the theme tokens in src/assets/main.css. Kept as literal hex here
// because the canvas-based chart library cannot consume CSS custom properties.
export const CHART_COLORS = {
  surface: '#fcfcfb',
  hairline: '#e1e0d9',
  axis: '#c3c2b7',
  inkMuted: '#898781',
  nav: '#2a78d6',
  price: '#eb6834',
  primary: '#0f766e',
} as const
