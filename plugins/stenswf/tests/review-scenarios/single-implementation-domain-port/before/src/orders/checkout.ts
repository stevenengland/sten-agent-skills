import Stripe from 'stripe'

const stripe = new Stripe(process.env.STRIPE_KEY ?? '')

export async function checkout(orderId: string, cents: number): Promise<'paid' | 'declined'> {
  const intent = await stripe.paymentIntents.create({ amount: cents, currency: 'eur', metadata: { orderId } })
  return intent.status === 'succeeded' ? 'paid' : 'declined'
}
