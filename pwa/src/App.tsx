import { Routes, Route } from 'react-router-dom';
import { IOSRedirectBanner } from './components/IOSRedirectBanner';
import { IncidentListScreen } from './features/incidents/IncidentListScreen';
import { IncidentDetailStub } from './features/incidents/IncidentDetailStub';

export default function App() {
  return (
    <div className="min-h-full">
      <IOSRedirectBanner />
      <Routes>
        <Route path="/" element={<IncidentListScreen />} />
        <Route path="/incident/:id" element={<IncidentDetailStub />} />
      </Routes>
    </div>
  );
}
