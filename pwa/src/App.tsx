import { Routes, Route } from 'react-router-dom';

export default function App() {
  return (
    <div className="min-h-full">
      <Routes>
        <Route path="/" element={<Placeholder />} />
      </Routes>
    </div>
  );
}

function Placeholder() {
  return (
    <div className="flex items-center justify-center p-8">
      <h1 className="text-2xl font-semibold">BeNeM PWA</h1>
    </div>
  );
}
