import { Link, useParams } from 'react-router-dom';

export function IncidentDetailStub() {
  const { id } = useParams();
  return (
    <div className="p-6">
      <Link to="/" className="text-sm text-slate-400 hover:text-slate-200">
        ← Back
      </Link>
      <h1 className="mt-4 text-xl font-semibold">Incident {id}</h1>
      <p className="mt-2 text-sm text-slate-400">Incident detail coming in v0.1.1.</p>
    </div>
  );
}
