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

vi.mock('../useIncidents', () => ({
  useIncidents: vi.fn(() => ({
    data: parseIncidentsResponse(SERVED),
    isLoading: false, isError: false, error: null, dataUpdatedAt: Date.now(),
  })),
  useRefreshIncidents: vi.fn(() => ({ refresh, isRefreshing: false })),
  useRefreshOnForeground: vi.fn(),
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

  it('gives the selected pill its own state colour', async () => {
    // TOTAL is #7C3AED, the same in both states, exactly like the other four.
    // It replaced #1B0F33 — the app icon's measured dominant colour, and the
    // wrong value: the icon's dominant colour is its dark BACKGROUND, so the
    // selected pill was a near-black block on a near-black page and did not
    // read as selected at all. iOS asserts the identical string.
    renderScreen();
    expect(pill('TOTAL').style.backgroundColor).toBe('rgb(124, 58, 237)');  // #7C3AED
    expect(pill('TOTAL').style.color).toBe('rgb(255, 255, 255)');           // 5.6:1 on it
    await userEvent.click(pill('OPEN'));
    expect(pill('OPEN').style.backgroundColor).toBe('rgb(220, 38, 38)');
    await userEvent.click(pill('ACKD'));
    expect(pill('ACKD').style.backgroundColor).toBe('rgb(37, 99, 235)');
    await userEvent.click(pill('CLRD'));
    expect(pill('CLRD').style.backgroundColor).toBe('rgb(5, 150, 105)');
    await userEvent.click(pill('CLSD'));
    expect(pill('CLSD').style.backgroundColor).toBe('rgb(100, 116, 139)');
    await userEvent.click(pill('TOTAL'));
    expect(pill('TOTAL').style.backgroundColor).toBe('rgb(124, 58, 237)');
  });

  it('draws the two glow radii, and TOTAL is #7C3AED in BOTH states', async () => {
    // **The hex and the two radii — the whole of the mockup that can be
    // asserted rather than looked at.** No pill has a second colour any more:
    // fill, border, text and glow are one value each, and #1B0F33 is gone.
    renderScreen();

    const total = pill('TOTAL');                       // selected: 14px at 85%
    expect(total.style.backgroundColor).toBe('rgb(124, 58, 237)');  // #7C3AED FILLS it
    expect(total.style.boxShadow).toBe('0 0 14px #7C3AEDD9');       // and glows it
    expect(total.style.borderColor).toBe('rgb(124, 58, 237)');
    expect(total.style.borderWidth).toBe('1.5px');

    const open = pill('OPEN');                         // unselected: 4px at 55%
    expect(open.style.backgroundColor).toBe('transparent');
    expect(open.style.boxShadow).toBe('0 0 4px #DC26268C');
    expect(open.style.color).toBe('rgb(220, 38, 38)');  // text in the pill's own colour
    expect(open.style.borderColor).toBe('rgb(220, 38, 38)');

    // And the radii swap with the selection, rather than being stuck on one pill.
    // An UNSELECTED TOTAL is the same violet, hollow: transparent fill, violet
    // border, violet text, 4px violet glow — the rule the other four follow.
    await userEvent.click(pill('OPEN'));
    expect(pill('OPEN').style.boxShadow).toBe('0 0 14px #DC2626D9');
    expect(pill('TOTAL').style.boxShadow).toBe('0 0 4px #7C3AED8C');
    expect(pill('TOTAL').style.backgroundColor).toBe('transparent');
    expect(pill('TOTAL').style.color).toBe('rgb(124, 58, 237)');

    // box-shadow, never filter: drop-shadow — a filter would blur the digits.
    for (const p of ['TOTAL', 'OPEN', 'ACKD', 'CLRD', 'CLSD']) {
      expect(pill(p).style.filter).toBe('');
    }
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
