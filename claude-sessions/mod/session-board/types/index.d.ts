export type SessionRow = {
  id: string
  title: string
  group: string
  parentId: string
  isRunning: boolean
  lastActivityAt: number
  link: string
}

export type ReminderRow = {
  id: string
  title: string
  nextRunAt: number
}

export type Board = {
  sessions: SessionRow[]
  reminders: ReminderRow[]
  updatedAt: number
  error: string
}

declare module 'claude-code' {
  interface PluginState {
    'session-board': { board: Shaped<Board> }
  }
}
