import { describe, it, expect, beforeEach } from 'vitest';
import { loadApiKey, saveApiKey, clearApiKey, loadPin, savePin, clearPin } from '../settingsStorage';

describe('settingsStorage', () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it('returns null when no key is stored', () => {
    expect(loadApiKey()).toBeNull();
  });

  it('round-trips save and load', () => {
    saveApiKey('abc123');
    expect(loadApiKey()).toBe('abc123');
  });

  it('trims whitespace on save', () => {
    saveApiKey('  abc123  \n');
    expect(loadApiKey()).toBe('abc123');
  });

  it('clear removes the stored key', () => {
    saveApiKey('abc123');
    clearApiKey();
    expect(loadApiKey()).toBeNull();
  });
});

describe('PIN storage', () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it('returns null when no PIN is stored', () => {
    expect(loadPin()).toBeNull();
  });

  it('round-trips save and load', () => {
    savePin('mypin');
    expect(loadPin()).toBe('mypin');
  });

  it('trims whitespace on save', () => {
    savePin('  mypin  \n');
    expect(loadPin()).toBe('mypin');
  });

  it('clear removes the stored PIN', () => {
    savePin('mypin');
    clearPin();
    expect(loadPin()).toBeNull();
  });
});
