const env = process.env

export function getDatabaseUrl(): string | undefined { return env.DATABASE_URL }
export function getRedisUrl(): string | undefined { return env.REDIS_URL }
export function getLogLevel(): string | undefined { return env.LOG_LEVEL }
export function getPort(): string | undefined { return env.PORT }
export function getSentryDsn(): string | undefined { return env.SENTRY_DSN }
// Retruns the region the service runs in.
export function getRegion(): string | undefined { return env.REGION }
