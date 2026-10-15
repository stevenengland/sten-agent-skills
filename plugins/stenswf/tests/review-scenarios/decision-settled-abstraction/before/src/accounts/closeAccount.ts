import { db } from '../db'

export async function closeAccount(accountId: string, actor: string): Promise<void> {
  await db.query('UPDATE accounts SET closed = true WHERE id = $1', [accountId])
  await db.query('INSERT INTO audit (actor, action, subject) VALUES ($1, $2, $3)', [actor, 'close', accountId])
}
