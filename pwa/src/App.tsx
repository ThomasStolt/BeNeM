import { useEffect } from 'react';
import { Routes, Route, useNavigate } from 'react-router-dom';
import { IOSRedirectBanner } from './components/IOSRedirectBanner';
import { IncidentListScreen } from './features/incidents/IncidentListScreen';
import { IncidentDetailScreen } from './features/incidents/IncidentDetailScreen';
import { SettingsScreen } from './features/settings/SettingsScreen';

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
    <div className="min-h-full">
      <IOSRedirectBanner />
      <Routes>
        <Route path="/" element={<IncidentListScreen />} />
        <Route path="/settings" element={<SettingsScreen />} />
        <Route path="/incident/:id" element={<IncidentDetailScreen />} />
      </Routes>
    </div>
  );
}
