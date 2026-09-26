/// <reference types="vite/client" />

interface ImportMetaEnv {
  // Privy's public app ID. Safe to ship in the bundle; the app secret and
  // authorization keys are server-side only and must never appear here.
  readonly VITE_PRIVY_APP_ID?: string
  // Selects a deployment from config/addresses.json when it holds more than one.
  readonly VITE_CHAIN_ID?: string
}
