import { Routes, Route } from 'react-router-dom';
import { IOSRedirectBanner } from './components/IOSRedirectBanner';
import { IncidentListScreen } from './features/incidents/IncidentListScreen';
import { IncidentDetailScreen } from './features/incidents/IncidentDetailScreen';
import { SettingsScreen } from './features/settings/SettingsScreen';

export default function App() {
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
