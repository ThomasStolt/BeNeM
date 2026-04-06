import { describe, it, expect, beforeEach } from 'vitest';
import {
  type ServerConfig,
  loadServers,
  saveServers,
  addServer,
  updateServer,
  removeServer,
  getActiveServer,
  setActiveServer,
  createServerConfig,
  migrateFromLegacyConfig,
} from '../serverStorage';

beforeEach(() => {
  localStorage.clear();
});

describe('serverStorage', () => {
  describe('loadServers / saveServers', () => {
    it('returns empty array when nothing stored', () => {
      expect(loadServers()).toEqual([]);
    });

    it('round-trips a server list', () => {
      const servers: ServerConfig[] = [
        createServerConfig({ name: 'Test', baseUrl: '/bhnm', apiKey: 'key1' }),
      ];
      saveServers(servers);
      const loaded = loadServers();
      expect(loaded).toHaveLength(1);
      expect(loaded[0].name).toBe('Test');
      expect(loaded[0].apiKey).toBe('key1');
    });
  });

  describe('addServer', () => {
    it('adds a server and sets it active if first', () => {
      const server = addServer({ name: 'First', baseUrl: '/bhnm', apiKey: 'k1' });
      const servers = loadServers();
      expect(servers).toHaveLength(1);
      expect(servers[0].isActive).toBe(true);
      expect(servers[0].id).toBe(server.id);
    });

    it('adds a second server as inactive', () => {
      addServer({ name: 'First', baseUrl: '/bhnm', apiKey: 'k1' });
      addServer({ name: 'Second', baseUrl: '/bhnm2', apiKey: 'k2' });
      const servers = loadServers();
      expect(servers).toHaveLength(2);
      expect(servers[0].isActive).toBe(true);
      expect(servers[1].isActive).toBe(false);
    });
  });

  describe('updateServer', () => {
    it('updates fields on existing server', () => {
      const server = addServer({ name: 'Old', baseUrl: '/bhnm', apiKey: 'k1' });
      updateServer(server.id, { name: 'New', apiKey: 'k2' });
      const loaded = loadServers();
      expect(loaded[0].name).toBe('New');
      expect(loaded[0].apiKey).toBe('k2');
      expect(loaded[0].baseUrl).toBe('/bhnm'); // unchanged
    });
  });

  describe('removeServer', () => {
    it('removes by id', () => {
      const s1 = addServer({ name: 'A', baseUrl: '/a', apiKey: 'ka' });
      addServer({ name: 'B', baseUrl: '/b', apiKey: 'kb' });
      removeServer(s1.id);
      const servers = loadServers();
      expect(servers).toHaveLength(1);
      expect(servers[0].name).toBe('B');
    });

    it('activates next server if active one is removed', () => {
      const s1 = addServer({ name: 'A', baseUrl: '/a', apiKey: 'ka' });
      addServer({ name: 'B', baseUrl: '/b', apiKey: 'kb' });
      removeServer(s1.id);
      const servers = loadServers();
      expect(servers[0].isActive).toBe(true);
    });
  });

  describe('getActiveServer', () => {
    it('returns null when no servers', () => {
      expect(getActiveServer()).toBeNull();
    });

    it('returns the active server', () => {
      addServer({ name: 'A', baseUrl: '/a', apiKey: 'ka' });
      const s2 = addServer({ name: 'B', baseUrl: '/b', apiKey: 'kb' });
      setActiveServer(s2.id);
      expect(getActiveServer()!.name).toBe('B');
    });
  });

  describe('setActiveServer', () => {
    it('deactivates other servers', () => {
      addServer({ name: 'A', baseUrl: '/a', apiKey: 'ka' });
      const s2 = addServer({ name: 'B', baseUrl: '/b', apiKey: 'kb' });
      setActiveServer(s2.id);
      const servers = loadServers();
      expect(servers[0].isActive).toBe(false);
      expect(servers[1].isActive).toBe(true);
    });
  });

  describe('migrateFromLegacyConfig', () => {
    it('creates server from legacy keys', () => {
      localStorage.setItem('benem:bhnm-api-key', 'legacy-key');
      localStorage.setItem('benem:bhnm-pin', 'legacy-pin');
      localStorage.setItem('benem:webhook-secret', 'legacy-secret');
      localStorage.setItem('benem:push-enabled', 'true');

      migrateFromLegacyConfig();

      const servers = loadServers();
      expect(servers).toHaveLength(1);
      expect(servers[0].apiKey).toBe('legacy-key');
      expect(servers[0].pin).toBe('legacy-pin');
      expect(servers[0].pushWebhookSecret).toBe('legacy-secret');
      expect(servers[0].pushEnabled).toBe(true);
      expect(servers[0].baseUrl).toBe('/bhnm');
      expect(servers[0].isActive).toBe(true);
      expect(servers[0].name).toBe('BHNM Server');
    });

    it('skips migration if servers already exist', () => {
      addServer({ name: 'Existing', baseUrl: '/bhnm', apiKey: 'k1' });
      localStorage.setItem('benem:bhnm-api-key', 'legacy-key');

      migrateFromLegacyConfig();

      const servers = loadServers();
      expect(servers).toHaveLength(1);
      expect(servers[0].name).toBe('Existing');
    });

    it('skips migration if no legacy keys', () => {
      migrateFromLegacyConfig();
      expect(loadServers()).toEqual([]);
    });

    it('removes legacy keys after migration', () => {
      localStorage.setItem('benem:bhnm-api-key', 'legacy-key');
      migrateFromLegacyConfig();
      expect(localStorage.getItem('benem:bhnm-api-key')).toBeNull();
      expect(localStorage.getItem('benem:bhnm-pin')).toBeNull();
      expect(localStorage.getItem('benem:webhook-secret')).toBeNull();
      expect(localStorage.getItem('benem:push-enabled')).toBeNull();
    });
  });
});
