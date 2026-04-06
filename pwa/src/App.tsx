import { useEffect } from 'react';
import { Routes, Route, useNavigate } from 'react-router-dom';
import { AppLayout } from './components/AppLayout';
import { DashboardScreen } from './features/dashboard/DashboardScreen';
import { IncidentListScreen } from './features/incidents/IncidentListScreen';
import { IncidentDetailScreen } from './features/incidents/IncidentDetailScreen';
import { SettingsScreen } from './features/settings/SettingsScreen';
import { DeviceListScreen } from './features/devices/DeviceListScreen';
import { DeviceDetailScreen } from './features/devices/DeviceDetailScreen';
import { TacticalGroupListScreen } from './features/tactical/TacticalGroupListScreen';

export default function App() {
  const navigate = useNavigate();

  useEffect(() => {
    if (!('serviceWorker' in navigator)) return;

    const handler = (event: MessageEvent) => {
      if (event.data?.type === 'navigate' && typeof event.data.url === 'string') {
        navigate(event.data.url);
      }
    };

    navigator.serviceWorker.addEventListener('message', handler);
    return () => navigator.serviceWorker.removeEventListener('message', handler);
  }, [navigate]);

  return (
    <Routes>
      <Route element={<AppLayout />}>
        <Route path="/" element={<DashboardScreen />} />
        <Route path="/incidents" element={<IncidentListScreen />} />
        <Route path="/incidents/:id" element={<IncidentDetailScreen />} />
        <Route path="/devices" element={<DeviceListScreen />} />
        <Route path="/devices/:name" element={<DeviceDetailScreen />} />
        <Route path="/tactical/:type" element={<TacticalGroupListScreen />} />
      </Route>
      <Route path="/settings" element={<SettingsScreen />} />
    </Routes>
  );
}
