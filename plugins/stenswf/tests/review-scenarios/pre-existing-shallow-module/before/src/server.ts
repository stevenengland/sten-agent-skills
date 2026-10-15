import { getPort, getRegion } from './config/settings'

export function banner(): string {
  return `listening on ${getPort() ?? '8080'} in ${getRegion() ?? 'local'}`
}
