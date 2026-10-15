import { checkout } from './orders/checkout'

export async function placeOrder(orderId: string, cents: number) {
  return checkout(orderId, cents)
}
