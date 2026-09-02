import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { DeviceRow } from '../DeviceRow';

const device = {
  name: 'core-switch-01', ip: '10.0.0.1', category: 'Network', site: 'HQ',
  model: '', serialNumber: '', description: '', deviceIndex: '', status: 'up' as const,
};

function renderRow(inMaintenance: boolean) {
  return render(
    <MemoryRouter>
      <DeviceRow device={device} inMaintenance={inMaintenance} />
    </MemoryRouter>,
  );
}

describe('DeviceRow maintenance marker', () => {
  it('shows the blue wrench beside the name when in maintenance', () => {
    renderRow(true);
    expect(screen.getByLabelText('In maintenance')).toBeInTheDocument();
  });

  it('shows no marker otherwise', () => {
    renderRow(false);
    expect(screen.queryByLabelText('In maintenance')).not.toBeInTheDocument();
  });
});
