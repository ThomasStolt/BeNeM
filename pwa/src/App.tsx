import { useEffect } from 'react';
import { Routes, Route, useNavigate } from 'react-router-dom';
import { AppLayout } from './components/AppLayout';
import { DashboardScreen } from './features/dashboard/DashboardScreen';
import { IncidentListScreen } from './features/incidents/IncidentListScreen';
import { IncidentDetailScreen } from './features/incidents/IncidentDetailScreen';
import { SettingsScreen } from './features/settings/SettingsScreen';
import { DevicesPlaceholder } from './features/devices/DevicesPlaceholder';

export default function App() {
  const navigate = useNavigate();

  // Listen for navigation messages from the service worker (push notification clicks)
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
        <Route path="/devices" element={<DevicesPlaceholder />} />
      </Route>
      <Route path="/settings" element={<SettingsScreen />} />
    </Routes>
  );
}
