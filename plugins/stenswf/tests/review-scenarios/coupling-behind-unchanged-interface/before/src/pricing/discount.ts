import { TIERS } from './internal/tiers'

/** The one place loyalty discounts are decided. */
export function discountFor(customerTier: string, cents: number): number {
  const rate = TIERS[customerTier] ?? 0
  return Math.round(cents * rate)
}
