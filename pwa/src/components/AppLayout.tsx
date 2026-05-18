import { Outlet } from 'react-router-dom';
import { TabBar } from './TabBar';
import { IOSRedirectBanner } from './IOSRedirectBanner';

export function AppLayout() {
  return (
    <div className="flex flex-col h-dvh">
      <IOSRedirectBanner />
      <div className="flex-1 overflow-y-auto min-h-0">
        <Outlet />
      </div>
      <TabBar />
    </div>
  );
}
