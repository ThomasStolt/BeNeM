import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { TabBar } from '../TabBar';

function renderWithRouter(initialEntry = '/') {
  return render(
    <MemoryRouter initialEntries={[initialEntry]}>
      <TabBar />
    </MemoryRouter>,
  );
}

describe('TabBar', () => {
  it('renders three tabs', () => {
    renderWithRouter();
    expect(screen.getByRole('link', { name: /dashboard/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /incidents/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /devices/i })).toBeInTheDocument();
  });

  it('highlights active tab based on route', () => {
    renderWithRouter('/incidents');
    const incidentsTab = screen.getByRole('link', { name: /incidents/i });
    expect(incidentsTab.className).toContain('text-sky-400');
  });

  it('highlights dashboard on root route', () => {
    renderWithRouter('/');
    const dashTab = screen.getByRole('link', { name: /dashboard/i });
    expect(dashTab.className).toContain('text-sky-400');
  });
});
