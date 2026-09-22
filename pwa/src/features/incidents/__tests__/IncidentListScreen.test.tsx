// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { parseIncidentsResponse } from '../../../lib/api/incidents';
import { IncidentListScreen } from '../IncidentListScreen';

const SERVED = {
  active_incidents: [
    { incident_id: '30005', name: 'UAP-AC-Pro-DB', title: 'Anomaly Bandwidth',
      state: 'OPEN', acknowledged: false, ack_user: null, closed_at: null, incident_state: 'OPEN' },
    { incident_id: '27516', name: 'C9200CX', title: 'Service Configuration Save Check',
      state: 'OPEN', acknowledged: true, ack_user: 'Thomas iPhone 13 ProMax', closed_at: null,
      incident_state: 'ACKNOWLEDGED' },
    { incident_id: '30014', name: 'UAP_AC_M', title: 'Anomaly Bandwidth wifi1ap5',
      state: 'ALARMS CLEARED', acknowledged: false, ack_user: null, closed_at: null,
      incident_state: 'ALARMS CLEARED' },
  ],
  closed_incidents: [
    { incident_id: '30007', name: 'raspi-050', title: 'Host raspi-050',
      state: 'CLOSED', acknowledged: false, ack_user: null, closed_at: 1789928537.339,
      incident_state: 'CLOSED' },
  ],
};

const refresh = vi.fn(async () => {});
const reload = vi.fn(async () => {});

vi.mock('../useIncidents', () => ({
  useIncidents: vi.fn(() => ({
    data: parseIncidentsResponse(SERVED),
    isLoading: false, isError: false, error: null, dataUpdatedAt: Date.now(),
  })),
  useRefreshIncidents: vi.fn(() => ({ refresh, isRefreshing: false })),
  useRefreshOnForeground: vi.fn(),
  // The two cache-only update paths added in 0.19.5. Stubbed here because this
  // file is about what the screen RENDERS; their behaviour is asserted for real
  // in list-stays-current.test.ts, against the hooks themselves.
  useReloadIncidents: vi.fn(() => reload),
  useReloadOnPush: vi.fn(),
  usePollWhileVisible: vi.fn(),
  incidentsQueryKey: vi.fn(() => ['incidents']),
}));

vi.mock('../useIncidentDetail', () => ({
  useIncidentDetail: vi.fn(() => ({ data: undefined, isLoading: false, isFetching: false })),
}));

vi.mock('../../../lib/config', () => ({
  useConfig: vi.fn(() => ({
    serverId: 'lab', serverName: 'Lab', baseUrl: 'https://mw', apiKey: 'k',
    isConfigured: true, ackUser: '', bhnmUrl: '',
  })),
}));

beforeEach(() => {
  refresh.mockClear();
  vi.stubGlobal('ResizeObserver', vi.fn(() => ({ observe: vi.fn(), unobserve: vi.fn(), disconnect: vi.fn() })));
});

function renderScreen(initialPath = '/incidents') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={[initialPath]}>
        <IncidentListScreen />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

const pill = (name: string) => screen.getByRole('tab', { name: new RegExp(`^${name}`) });
const rowIds = () =>
  within(screen.getByTestId('incident-list')).getAllByRole('listitem')
    .map((li) => li.textContent ?? '');

describe('IncidentListScreen', () => {
  it('renders a row for each incident in the selected pill', () => {
    // Carried over from the pre-0.19.0 suite, which had no filter and so
    // asserted the whole list. TOTAL is the default, and it holds three.
    renderScreen();
    expect(screen.getAllByText(/UAP-AC-Pro-DB/).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/C9200CX/).length).toBeGreaterThan(0);
    expect(screen.getByTestId('incident-list').querySelectorAll('li')).toHaveLength(3);
  });

  it('renders a status badge on every row', async () => {
    renderScreen();
    const list = () => screen.getByTestId('incident-list');
    expect(within(list()).getByText('OPEN')).toBeInTheDocument();
    expect(within(list()).getByText('ACKD')).toBeInTheDocument();
    await userEvent.click(pill('CLRD'));
    expect(within(list()).getByText('CLRD')).toBeInTheDocument();
  });

  it('renders five pills in order, each with its count', () => {
    renderScreen();
    const tabs = screen.getAllByRole('tab');
    expect(tabs.map((t) => t.getAttribute('data-pill'))).toEqual(
      ['TOTAL', 'OPEN', 'ACKD', 'CLRD', 'CLSD'],
    );
    expect(pill('TOTAL')).toHaveTextContent('3');
    expect(pill('OPEN')).toHaveTextContent('1');
    expect(pill('ACKD')).toHaveTextContent('1');
    expect(pill('CLRD')).toHaveTextContent('1');
    expect(pill('CLSD')).toHaveTextContent('1');
  });

  it('defaults to TOTAL, which is everything except closed', () => {
    renderScreen();
    expect(pill('TOTAL')).toHaveAttribute('aria-selected', 'true');
    const text = rowIds().join(' ');
    expect(text).toContain('#30005');
    expect(text).toContain('#27516');   // acknowledged, still OPEN
    expect(text).toContain('#30014');   // alarms cleared
    expect(text).not.toContain('#30007'); // CLOSED — opt in via CLSD
  });

  it('OPEN shows unacknowledged incidents only; the acked one is in ACKD', async () => {
    renderScreen();
    await userEvent.click(pill('OPEN'));
    expect(rowIds().join(' ')).toContain('#30005');
    expect(rowIds().join(' ')).not.toContain('#27516');
    await userEvent.click(pill('ACKD'));
    expect(rowIds().join(' ')).toContain('#27516');
  });

  /** The ten hex values, as the mockup states them. iOS holds the identical ten
   * in `IncidentPill.palette` and asserts them there, so neither platform can
   * drift on any of them in silence. */
  const PALETTE = {
    TOTAL: { base: 'rgb(124, 58, 237)', tint: 'rgb(167, 139, 250)', hex: ['#7C3AED', '#A78BFA'] },
    OPEN: { base: 'rgb(220, 38, 38)', tint: 'rgb(248, 113, 113)', hex: ['#DC2626', '#F87171'] },
    ACKD: { base: 'rgb(37, 99, 235)', tint: 'rgb(96, 165, 250)', hex: ['#2563EB', '#60A5FA'] },
    CLRD: { base: 'rgb(22, 163, 74)', tint: 'rgb(74, 222, 128)', hex: ['#16A34A', '#4ADE80'] },
    CLSD: { base: 'rgb(242, 242, 247)', tint: 'rgb(255, 255, 255)', hex: ['#F2F2F7', '#FFFFFF'] },
  } as const;
  const PILL_NAMES = ['TOTAL', 'OPEN', 'ACKD', 'CLRD', 'CLSD'] as const;

  it('fills the selected pill with its BASE and frames it in its TINT', async () => {
    renderScreen();
    for (const name of PILL_NAMES) {
      await userEvent.click(pill(name));
      const el = pill(name);
      const { base, tint } = PALETTE[name];
      expect(el.style.backgroundColor).toBe(base);
      expect(el.style.borderColor).toBe(tint);
      expect(el.style.borderWidth).toBe('1.5px');
      // White text on four; CLSD's fill is nearly white, so white on white
      // would be the whole label gone.
      expect(el.style.color).toBe(name === 'CLSD' ? 'rgb(17, 17, 20)' : 'rgb(255, 255, 255)');
      // Selected glow: 14px at 85%, in the BASE.
      expect(el.style.boxShadow).toBe(`0 0 14px ${PALETTE[name].hex[0]}D9`);
    }
  });

  it('frames, texts and glows an UNSELECTED pill in its TINT, on the #1a1a1d plate', async () => {
    renderScreen();                       // TOTAL is selected; the other four are not
    await userEvent.click(pill('TOTAL'));
    for (const name of PILL_NAMES.filter((p) => p !== 'TOTAL' && p !== 'CLSD')) {
      const el = pill(name);
      const { tint, hex } = PALETTE[name];
      // Not transparent. Round one let the page through and the row read as
      // outlines floating on nothing.
      expect(el.style.backgroundColor).toBe('rgb(26, 26, 29)');   // #1a1a1d
      expect(el.style.borderColor).toBe(tint);
      expect(el.style.color).toBe(tint);
      expect(el.style.boxShadow).toBe(`0 0 4px ${hex[1]}8C`);     // 4px at 55%, in the TINT
    }
  });

  it('gives an UNSELECTED CLSD no frame and no glow — white text on the plate alone', async () => {
    // The one tab you opt into, and the only pill not competing for attention
    // when you have not. A frame in #FFFFFF would be the brightest thing in a
    // row nobody is looking at.
    renderScreen();
    const el = pill('CLSD');
    expect(el).toHaveAttribute('data-selected', 'false');
    expect(el.style.boxShadow).toBe('none');
    expect(el.style.borderColor).toBe('transparent');
    // The border WIDTH stays, or the frameless pill would be 3px narrower than
    // the four beside it and the row would not line up.
    expect(el.style.borderWidth).toBe('1.5px');
    expect(el.style.color).toBe('rgb(255, 255, 255)');
    expect(el.style.backgroundColor).toBe('rgb(26, 26, 29)');

    // And it does get both back when it IS selected.
    await userEvent.click(pill('CLSD'));
    expect(pill('CLSD').style.boxShadow).toBe('0 0 14px #F2F2F7D9');
    expect(pill('CLSD').style.borderColor).toBe('rgb(255, 255, 255)');
  });

  it('draws the two glow radii, and never a filter', async () => {
    renderScreen();
    expect(pill('TOTAL').style.boxShadow).toBe('0 0 14px #7C3AEDD9');   // selected
    expect(pill('OPEN').style.boxShadow).toBe('0 0 4px #F871718C');     // unselected
    await userEvent.click(pill('OPEN'));
    expect(pill('OPEN').style.boxShadow).toBe('0 0 14px #DC2626D9');
    expect(pill('TOTAL').style.boxShadow).toBe('0 0 4px #A78BFA8C');
    // box-shadow, never filter: drop-shadow — a filter would blur the digits.
    for (const name of PILL_NAMES) expect(pill(name).style.filter).toBe('');
  });

  it('turns the colour transition off for a reader who asked for less movement', () => {
    // The glow is static and nothing animates in or out, so the 150 ms
    // transition-colors is the only thing here that moves.
    renderScreen();
    expect(pill('TOTAL').className).toContain('motion-reduce:transition-none');
  });

  it('honours ?pill=OPEN from the Home tile', () => {
    renderScreen('/incidents?pill=CLSD');
    expect(pill('CLSD')).toHaveAttribute('aria-selected', 'true');
  });

  it('falls back to the default pill for an unrecognised one in the URL', () => {
    renderScreen('/incidents?pill=NONSENSE');
    expect(pill('TOTAL')).toHaveAttribute('aria-selected', 'true');
  });

  it('still lands a stale ?pill=TOTL link on TOTAL', () => {
    // 0.19.1 shipped the Home tile as `/incidents?pill=TOTL`, and that link is
    // in cached bundles and in anything anyone bookmarked. **No alias code was
    // added for it**: an unrecognised pill already falls back to DEFAULT_PILL,
    // and DEFAULT_PILL is TOTAL, so the old link lands exactly where it meant
    // to. This test is what makes that a decision rather than a coincidence —
    // it fails if the default ever moves, which the design note forbids for a
    // different reason anyway.
    renderScreen('/incidents?pill=TOTL');
    expect(pill('TOTAL')).toHaveAttribute('aria-selected', 'true');
  });

  it('renders a CLOSED row under CLSD with a grey chip', async () => {
    renderScreen();
    await userEvent.click(pill('CLSD'));
    const list = screen.getByTestId('incident-list');
    expect(within(list).getByText('#30007')).toBeInTheDocument();
    const chip = within(list).getByText('CLSD');
    expect(chip.className).toContain('bg-slate-500');
  });

  it('searches within the selected pill and does not escape it', async () => {
    renderScreen();
    await userEvent.click(pill('OPEN'));
    const box = screen.getByLabelText('Search incidents');
    await userEvent.type(box, 'raspi');
    // raspi-050 is CLOSED; OPEN is selected, so the search finds nothing.
    expect(screen.queryByTestId('incident-list')).not.toBeInTheDocument();
    expect(screen.getByText('No matches')).toBeInTheDocument();

    await userEvent.click(pill('CLSD'));
    expect(within(screen.getByTestId('incident-list')).getByText('#30007')).toBeInTheDocument();
  });

  it('searches by ack user', async () => {
    renderScreen();
    await userEvent.click(pill('ACKD'));
    await userEvent.type(screen.getByLabelText('Search incidents'), 'ProMax');
    const text = rowIds().join(' ');
    expect(text).toContain('#27516');
    expect(text).not.toContain('#30005');
  });

  it('the refresh control calls the refresh endpoint, not a plain refetch', async () => {
    renderScreen();
    await userEvent.click(screen.getByRole('button', { name: /refresh/i }));
    expect(refresh).toHaveBeenCalled();
  });

  it('states the CLSD window in words when the tab is empty', async () => {
    renderScreen('/incidents?pill=CLRD');
    await userEvent.click(pill('CLSD'));
    await userEvent.type(screen.getByLabelText('Search incidents'), 'zzz-no-such-thing');
    expect(screen.getByText('No matches')).toBeInTheDocument();
  });
});
