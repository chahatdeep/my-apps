import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Board, ReminderRow, SessionRow } from '../types'

const PANE = 'session-board'
const TITLE = 'Sessions'
const POLL_MS = 20_000
const RECENT_MS = 24 * 60 * 60 * 1000
const RECENT_MAX = 8
// The card's folder: %USERPROFILE%\.claude\session-board (install.ps1 puts it there).
async function boardDir($: any): Promise<string> {
  const home = (await $.env.get('USERPROFILE')) ?? (await $.env.get('HOME')) ?? ''
  return `${home.split('\\').join('/')}/.claude/session-board`
}

// Palette: vivid accents that read on light and dark backgrounds.
const WORKING = '#10B981' // emerald
const RECENT = '#6366F1' // indigo
const REMIND = '#F59E0B' // amber
const GROUP_COLORS = ['#EC4899', '#06B6D4', '#8B5CF6', '#F97316', '#14B8A6', '#3B82F6', '#EAB308', '#F43F5E']

function groupColor(name: string): string {
  let h = 0
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0
  return GROUP_COLORS[h % GROUP_COLORS.length] ?? RECENT
}

const EMPTY: Board = { sessions: [], reminders: [], updatedAt: 0, error: '' }
// Change the tag when Board's fields change: it declines what an earlier
// version stored, which outlives a reload.
const board = atom({ plugin: 'session-board', key: 'board' } as const, EMPTY, {
  shape: 'board-2',
})

function textOf(result: { content: { type: string; text?: string }[] }): string {
  return result.content
    .map(block => (block.type === 'text' ? (block.text ?? '') : ''))
    .join('')
}

function ago(now: number, at: number): string {
  const s = Math.max(0, Math.round((now - at) / 1000))
  if (s < 60) return 'just now'
  const m = Math.round(s / 60)
  if (m < 60) return `${m}m ago`
  const h = Math.round(m / 60)
  if (h < 48) return `${h}h ago`
  return `${Math.round(h / 24)}d ago`
}

function until(now: number, at: number): string {
  const d = new Date(at)
  const when = d.toLocaleString('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
  const m = Math.round((at - now) / 60000)
  if (m < 0) return `${when} (due)`
  if (m < 60) return `${when} (in ${m}m)`
  const h = Math.round(m / 60)
  if (h < 48) return `${when} (in ${h}h)`
  return `${when} (in ${Math.round(h / 24)}d)`
}

async function refresh($: any): Promise<void> {
  const now: number = await $.clock.now()
  let error = ''
  let sessions: SessionRow[] = []
  let reminders: ReminderRow[] = []

  try {
    const res = await $.mcp.call('ccd_session_mgmt', 'list_sessions', { limit: 60 })
    if (res.isError) throw new Error(textOf(res))
    const raw = JSON.parse(textOf(res)) as any[]
    // list_sessions leaves out the calling session; add it so every writer
    // produces the same list.
    try {
      const self = await $.mcp.call('ccd_session_mgmt', 'get_session', { session_id: 'self' })
      if (!self.isError) raw.unshift(JSON.parse(textOf(self)))
    } catch {
      // Without it the list is still useful.
    }
    const seen = new Set<string>()
    sessions = raw
      .filter(s => !s.isArchived && !seen.has(s.sessionId) && seen.add(s.sessionId))
      .map(s => ({
        id: String(s.sessionId),
        title: String(s.title ?? 'Untitled'),
        group: String(s.group?.name ?? ''),
        parentId: String(s.parentSessionId ?? s.startedBy ?? ''),
        isRunning: Boolean(s.isRunning),
        lastActivityAt: Date.parse(s.lastActivityAt ?? '') || 0,
        link: String(s.link ?? ''),
      }))
  } catch (err) {
    error = `Sessions unavailable: ${String((err as Error)?.message ?? err).slice(0, 120)}`
  }

  try {
    const res = await $.mcp.call('scheduled-tasks', 'list_scheduled_tasks', {})
    if (!res.isError) {
      const raw = JSON.parse(textOf(res)) as any[]
      reminders = raw
        .filter(t => t.enabled && t.nextRunAt)
        .map(t => ({
          id: String(t.taskId),
          title: String(t.title ?? t.taskId),
          nextRunAt: Date.parse(t.nextRunAt) || 0,
        }))
        .filter(t => t.nextRunAt > 0)
        .sort((a, b) => a.nextRunAt - b.nextRunAt)
    }
  } catch {
    // Reminders are optional; leave the list empty.
  }

  await update($, board, prev => ({
    sessions: error ? prev.sessions : sessions,
    reminders,
    updatedAt: now,
    error,
  }))

  // Mirror the data to a file for the always-on-top desktop widget
  // (~/.claude/session-board/SessionBoard.ps1) to read.
  try {
    const snapshot: Board = await read($, board)
    await $.fs.write(`${await boardDir($)}/board.json`, JSON.stringify(snapshot))
  } catch {
    // The widget shows the data as stale; the pane is unaffected.
  }
}

// Starts the "Claude Sessions" card if it isn't running (it allows one copy).
// SessionBoard.vbs runs it with no console window: on Windows 11 a plain
// powershell.exe start opens a Windows Terminal tab, and closing that tab
// would close the card. wscript returns as soon as the card has started.
async function launchWidget($: any): Promise<void> {
  try {
    const vbs = `${await boardDir($)}/SessionBoard.vbs`.split('/').join('\\')
    await $.process.run(['wscript.exe', vbs], { timeoutMs: 10_000 })
  } catch {
    // The card is optional; nothing else depends on it.
  }
}

async function openSession($: any, link: string): Promise<void> {
  if (!link) return
  await $.process.run(['cmd.exe', '/c', 'start', '', link], { timeoutMs: 10_000 })
}

export const register: Register = on => {
  let timer: { cancel: () => void } | undefined

  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await $.command.register({
      name: 'sessions',
      description: 'Bring back the Claude Sessions card (working sessions, recent ones, reminders)',
    })
    // No pane opens by itself: the always-on-top desktop widget shows this
    // data. /sessions opens the in-app pane on demand.
    void refresh($)
    void launchWidget($)
    timer?.cancel()
    timer = $.clock.every(POLL_MS, () => {
      void refresh($)
    })
    return started
  })

  on('command.run', { command: 'sessions' }, async $ => {
    await refresh($)
    await launchWidget($)
    return { text: 'Claude Sessions card started (top right of the Claude window).' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const b = await read($, board)
    const now = b.updatedAt || (await $.clock.now())

    const working = b.sessions
      .filter(s => s.isRunning)
      .sort((x, y) => y.lastActivityAt - x.lastActivityAt)
    const recent = b.sessions
      .filter(s => !s.isRunning && now - s.lastActivityAt < RECENT_MS)
      .sort((x, y) => y.lastActivityAt - x.lastActivityAt)
      .slice(0, RECENT_MAX)

    const pill = (key: string, label: string, bg: string) => (
      <Box key={key} backgroundColor={bg} paddingX={1}>
        <Text bold color="#FFFFFF">{label}</Text>
      </Box>
    )

    const card = (
      key: string,
      accent: string,
      icon: string,
      title: string,
      count: number | null,
      body: any,
    ) => (
      <Box
        key={key}
        flexDirection="column"
        borderStyle="round"
        borderColor={accent}
        paddingX={1}
        gap={0}
      >
        <Box flexDirection="row" gap={1} alignItems="center" marginBottom={1}>
          <Text bold color={accent}>
            {icon} {title}
          </Text>
          {count === null ? null : pill(`${key}-n`, String(count), accent)}
        </Box>
        {body}
      </Box>
    )

    const row = (s: SessionRow, accent: string, pulse: boolean) => (
      <Box
        key={s.id}
        flexDirection="row"
        gap={1}
        paddingX={1}
        paddingY={0}
        marginBottom={1}
        hover={{ backgroundColor: '#8882' }}
      >
        <Box flexShrink={0}>
          <Text color={accent}>{pulse ? '◉' : '●'}</Text>
        </Box>
        <Box flexDirection="column" flexGrow={1} flexShrink={1} minWidth={0}>
          <Button key={`open-${s.id}`} plain onPress={() => openSession($, s.link)}>
            <Text weight="semibold" wrap="truncate-end">{s.title}</Text>
          </Button>
          <Text size="caption" wrap="truncate-end">
            {s.group ? <Text color={groupColor(s.group)}>{s.group}</Text> : null}
            <Text dimColor>
              {s.group ? '  ·  ' : ''}
              {ago(now, s.lastActivityAt)}
            </Text>
          </Text>
        </Box>
      </Box>
    )

    const empty = (text: string) => <Text dimColor italic>{text}</Text>

    if (e.props.placement === 'widget') {
      const next = b.reminders[0]
      return (
        <Box
          flexDirection="column"
          borderStyle="round"
          borderColor={working.length > 0 ? WORKING : RECENT}
          paddingX={1}
        >
          <Box flexDirection="row" gap={1} marginBottom={1}>
            {pill('w', `⚡ ${working.length}`, WORKING)}
            {pill('r', `✦ ${recent.length}`, RECENT)}
            {pill('t', `⏰ ${b.reminders.length}`, REMIND)}
          </Box>
          {working.length === 0 ? (
            <Text size="caption" dimColor italic>
              Nothing running
            </Text>
          ) : (
            working.slice(0, 3).map(s => (
              <Text key={`w-${s.id}`} size="caption" wrap="truncate-end">
                <Text color={WORKING}>◉ </Text>
                {s.title}
              </Text>
            ))
          )}
          {next ? (
            <Text size="caption" wrap="truncate-end">
              <Text color={REMIND}>⏰ </Text>
              {next.title}
              <Text dimColor> · {until(now, next.nextRunAt)}</Text>
            </Text>
          ) : null}
        </Box>
      )
    }

    return (
      <Box flexDirection="column" gap={1}>
        <Box flexDirection="row" gap={1} alignItems="center">
          {pill('h-w', `${working.length} working`, WORKING)}
          {pill('h-r', `${recent.length} recent`, RECENT)}
          {pill('h-t', `${b.reminders.length} reminder${b.reminders.length === 1 ? '' : 's'}`, REMIND)}
        </Box>

        {b.error ? (
          <Box borderStyle="round" borderColor="#EF4444" paddingX={1}>
            <Text color="#EF4444">{b.error}</Text>
          </Box>
        ) : null}

        {card(
          'working',
          WORKING,
          '⚡',
          'Working now',
          null,
          working.length === 0
            ? empty('Nothing running right now.')
            : working.map(s => row(s, WORKING, true)),
        )}

        {card(
          'recent',
          RECENT,
          '✦',
          'Recently active · 24h',
          null,
          recent.length === 0
            ? empty('No sessions in the last day.')
            : recent.map(s => row(s, RECENT, false)),
        )}

        {card(
          'reminders',
          REMIND,
          '⏰',
          'Upcoming reminders',
          null,
          b.reminders.length === 0
            ? empty('Nothing scheduled.')
            : b.reminders.map(r => (
                <Box key={r.id} flexDirection="column" paddingX={1} marginBottom={1}>
                  <Text bold>{r.title}</Text>
                  <Text color={REMIND}>{until(now, r.nextRunAt)}</Text>
                </Box>
              )),
        )}

        <Box flexDirection="row" gap={2} alignItems="center">
          <Button key="refresh" variant="primary" onPress={() => refresh($)}>
            ↻ Refresh
          </Button>
          <Text dimColor>
            {b.updatedAt ? `Updated ${ago(now, b.updatedAt)}` : 'Loading…'} · click a session to open it
          </Text>
        </Box>
      </Box>
    )
  })
}
