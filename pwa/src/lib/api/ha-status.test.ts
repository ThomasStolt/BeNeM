import { describe, it, expect } from 'vitest';
import { parseHaStatusResponse, formatHaRole, formatHaStatus } from './ha-status';

describe('parseHaStatusResponse', () => {
  it('parses array-wrapped response', () => {
    const result = parseHaStatusResponse([{ role: 'master', status: '1' }]);
    expect(result).toEqual({ role: 'master', status: '1' });
  });

  it('parses plain object response', () => {
    const result = parseHaStatusResponse({ role: 'standalone', status: '1' });
    expect(result).toEqual({ role: 'standalone', status: '1' });
  });

  it('throws on empty array', () => {
    expect(() => parseHaStatusResponse([])).toThrow();
  });

  it('throws on null', () => {
    expect(() => parseHaStatusResponse(null)).toThrow();
  });
});

describe('formatHaRole', () => {
  it('maps master to Primary', () => {
    expect(formatHaRole('master')).toBe('Primary');
  });
  it('maps primary to Primary', () => {
    expect(formatHaRole('primary')).toBe('Primary');
  });
  it('maps slave to Replica', () => {
    expect(formatHaRole('slave')).toBe('Replica');
  });
  it('maps standalone to Standalone', () => {
    expect(formatHaRole('standalone')).toBe('Standalone');
  });
  it('returns raw value for unknown roles', () => {
    expect(formatHaRole('unknown')).toBe('unknown');
  });
});

describe('formatHaStatus', () => {
  it('returns Active for primary status 1', () => {
    expect(formatHaStatus('primary', '1')).toBe('Active');
  });
  it('returns Inactive for primary status 2', () => {
    expect(formatHaStatus('primary', '2')).toBe('Inactive');
  });
  it('returns Takeover for slave status 2', () => {
    expect(formatHaStatus('slave', '2')).toBe('Takeover');
  });
  it('returns null for standalone', () => {
    expect(formatHaStatus('standalone', '1')).toBeNull();
  });
});
