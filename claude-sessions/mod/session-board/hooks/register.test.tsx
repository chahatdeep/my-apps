import { expect, test } from 'claude-code/testing'

const PANE = {
  plugin: 'session-board',
  component: 'Pane',
  requestId: 'session-board',
  props: {
    title: 'Sessions',
    isFocused: false,
    bodyColumns: 48,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

const NOW = Date.parse('2026-11-24T18:00:00Z')

const SESSIONS = [
  {
    sessionId: 'local_a',
    title: 'Refactor the parser',
    isArchived: false,
    isRunning: true,
    lastActivityAt: '2026-11-24T17:58:00Z',
    group: { id: 'g1', name: 'Work' },
    link: 'claude://claude.ai/epitaxy/local_a',
  },
  {
    sessionId: 'local_b',
    title: 'Plan the trip',
    isArchived: false,
    isRunning: false,
    lastActivityAt: '2026-11-24T11:32:00Z',
    group: { id: 'g2', name: 'Personal' },
    link: 'claude://claude.ai/epitaxy/local_b',
  },
]

const TASKS = [
  {
    taskId: 'weekly-review',
    title: 'Weekly review',
    enabled: true,
    nextRunAt: '2026-11-30T17:00:00.000Z',
  },
]

test('the pane draws sessions and reminders on every surface', async ($, on) => {
  on('command.register', () => ({ value: { command: 'sessions' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('clock.now', () => ({ value: NOW }))
  on('clock.every', () => ({ value: undefined }) as any)
  on('mcp.call', (_, e: any) => ({
    value: {
      isError: false,
      content: [
        { type: 'text', text: JSON.stringify(e.tool === 'list_sessions' ? SESSIONS : e.tool === 'get_session' ? SESSIONS[0] : TASKS) },
      ],
    },
  }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.command.run({ command: 'sessions', args: '' } as any)

  for (const surface of ['terminal', 'desktop', 'vscode', 'mobile'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Text', text: /Refactor the parser/ })).toBeTruthy()
    expect(await ui.find({ type: 'Text', text: /Plan the trip/ })).toBeTruthy()
    expect(await ui.find({ type: 'Text', text: /Weekly review/ })).toBeTruthy()
    await ui.unmount()
  }
})

test('the floating mini-card draws on desktop', async ($, on) => {
  on('command.register', () => ({ value: { command: 'sessions' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('clock.now', () => ({ value: NOW }))
  on('clock.every', () => ({ value: undefined }) as any)
  on('mcp.call', (_, e: any) => ({
    value: {
      isError: false,
      content: [
        { type: 'text', text: JSON.stringify(e.tool === 'list_sessions' ? SESSIONS : e.tool === 'get_session' ? SESSIONS[0] : TASKS) },
      ],
    },
  }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.command.run({ command: 'sessions', args: '' } as any)

  const ui = await $.ui.mount({
    ...PANE,
    surface: 'desktop',
    props: { ...PANE.props, placement: 'widget', anchors: ['bottom', 'right'] } as any,
  })
  expect(await ui.find({ type: 'Text', text: /Refactor the parser/ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /Weekly review/ })).toBeTruthy()
  await ui.unmount()
})
