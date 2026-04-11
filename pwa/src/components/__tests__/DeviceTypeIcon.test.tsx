import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/react';
import { DeviceTypeIcon } from '../DeviceTypeIcon';

describe('DeviceTypeIcon', () => {
  it('renders without crashing for each type', () => {
    const types = ['linux', 'windows', 'router', 'switch', 'unknown'] as const;
    for (const type of types) {
      const { container } = render(<DeviceTypeIcon type={type} status="up" size={40} />);
      expect(container.querySelector('svg')).not.toBeNull();
    }
  });

  it('applies blue background for status "up"', () => {
    const { container } = render(<DeviceTypeIcon type="linux" status="up" size={40} />);
    const wrapper = container.firstElementChild as HTMLElement;
    expect(wrapper.style.backgroundColor).toBe('rgb(2, 132, 199)');
  });

  it('applies red background for status "critical"', () => {
    const { container } = render(<DeviceTypeIcon type="linux" status="critical" size={40} />);
    const wrapper = container.firstElementChild as HTMLElement;
    expect(wrapper.style.backgroundColor).toBe('rgb(220, 38, 38)');
  });

  it('applies amber background for status "warning"', () => {
    const { container } = render(<DeviceTypeIcon type="router" status="warning" size={40} />);
    const wrapper = container.firstElementChild as HTMLElement;
    expect(wrapper.style.backgroundColor).toBe('rgb(217, 119, 6)');
  });

  it('renders at specified size', () => {
    const { container } = render(<DeviceTypeIcon type="switch" status="up" size={52} />);
    const wrapper = container.firstElementChild as HTMLElement;
    expect(wrapper.style.width).toBe('52px');
    expect(wrapper.style.height).toBe('52px');
  });
});
