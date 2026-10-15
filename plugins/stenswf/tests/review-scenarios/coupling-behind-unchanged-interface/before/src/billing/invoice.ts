import { discountFor } from '../pricing/discount'

export interface Invoice {
  customerTier: string
  totalCents: number
  discountCents: number
}

export function createInvoice(customerTier: string, totalCents: number): Invoice {
  return { customerTier, totalCents, discountCents: discountFor(customerTier, totalCents) }
}
