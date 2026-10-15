export interface User {
  id: string
  name: string
}

const users = new Map<string, User>()

export const userRepo = {
  find(id: string): User | undefined {
    return users.get(id)
  },
  save(user: User): void {
    users.set(user.id, user)
  },
}
