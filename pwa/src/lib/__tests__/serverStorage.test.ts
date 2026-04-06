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
});
