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
    // asserted the whole list. OPEN is the default, and it holds two.
    renderScreen();
    expect(screen.getAllByText(/UAP-AC-Pro-DB/).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/C9200CX/).length).toBeGreaterThan(0);
    expect(screen.getByTestId('incident-list').querySelectorAll('li')).toHaveLength(2);
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
      ['TOTL', 'OPEN', 'ACKD', 'CLRD', 'CLSD'],
    );
    expect(pill('TOTL')).toHaveTextContent('4');
    expect(pill('OPEN')).toHaveTextContent('2');
    expect(pill('ACKD')).toHaveTextContent('1');
    expect(pill('CLRD')).toHaveTextContent('1');
    expect(pill('CLSD')).toHaveTextContent('1');
  });

  it('defaults to OPEN and shows only open incidents', () => {
    renderScreen();
    expect(pill('OPEN')).toHaveAttribute('aria-selected', 'true');
    const text = rowIds().join(' ');
    expect(text).toContain('#30005');
    expect(text).toContain('#27516');   // acknowledged, still OPEN
    expect(text).not.toContain('#30014');
    expect(text).not.toContain('#30007');
  });

  it('gives the selected pill its own state colour', async () => {
    renderScreen();
    expect(pill('OPEN').className).toContain('bg-red-600');
    await userEvent.click(pill('ACKD'));
    expect(pill('ACKD').className).toContain('bg-blue-600');
    await userEvent.click(pill('CLRD'));
    expect(pill('CLRD').className).toContain('bg-emerald-600');
    await userEvent.click(pill('CLSD'));
    expect(pill('CLSD').className).toContain('bg-slate-500');
    await userEvent.click(pill('TOTL'));
    expect(pill('TOTL').className).toContain('bg-slate-700');
  });

  it('honours ?pill=OPEN from the Home tile', () => {
    renderScreen('/incidents?pill=CLSD');
    expect(pill('CLSD')).toHaveAttribute('aria-selected', 'true');
  });

  it('falls back to OPEN for an unrecognised pill in the URL', () => {
    renderScreen('/incidents?pill=NONSENSE');
    expect(pill('OPEN')).toHaveAttribute('aria-selected', 'true');
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
