import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { PerformanceSection } from './PerformanceSection';

vi.mock('./usePerformance', () => ({
  usePerformanceCategories: vi.fn(),
  usePerformanceInstances: vi.fn().mockReturnValue({ data: undefined }),
}));
vi.mock('../../lib/config', () => ({
  useConfig: () => ({
    serverId: 'test',
    serverName: 'Test',
    baseUrl: '/bhnm',
    apiKey: 'key',
    isConfigured: true,
  }),
}));

import { usePerformanceCategories } from './usePerformance';

function renderSection() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <PerformanceSection deviceIndex="3" deviceName="raspi-054" />
    </QueryClientProvider>,
  );
}

describe('PerformanceSection', () => {
  it('renders header text', () => {
    vi.mocked(usePerformanceCategories).mockReturnValue({
      data: [],
      isLoading: false,
      isError: false,
    } as unknown as ReturnType<typeof usePerformanceCategories>);

    renderSection();
    expect(screen.getByText(/Performance/)).toBeInTheDocument();
    expect(screen.getByText(/Last 24 Hours/)).toBeInTheDocument();
  });

  it('renders category cards when data is loaded', () => {
    vi.mocked(usePerformanceCategories).mockReturnValue({
      data: [
        { id: '5', category: 'Latency' },
        { id: '1', category: 'CPU' },
      ],
      isLoading: false,
      isError: false,
    } as unknown as ReturnType<typeof usePerformanceCategories>);

    renderSection();
    expect(screen.getByText('Latency')).toBeInTheDocument();
    expect(screen.getByText('CPU')).toBeInTheDocument();
  });

  it('shows loading state', () => {
    vi.mocked(usePerformanceCategories).mockReturnValue({
      data: undefined,
      isLoading: true,
      isError: false,
    } as unknown as ReturnType<typeof usePerformanceCategories>);

    renderSection();
    expect(screen.getByText(/Loading/i)).toBeInTheDocument();
  });
});
