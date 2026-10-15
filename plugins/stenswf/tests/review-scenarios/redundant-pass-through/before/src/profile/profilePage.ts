import { userRepo } from '../users/userRepo'

export function profileTitle(id: string): string {
  const user = userRepo.find(id)
  return user ? `Profile of ${user.name}` : 'Unknown user'
}
