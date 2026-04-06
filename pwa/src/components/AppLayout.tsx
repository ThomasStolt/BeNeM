import { Outlet } from 'react-router-dom';
import { TabBar } from './TabBar';
import { IOSRedirectBanner } from './IOSRedirectBanner';

export function AppLayout() {
  return (
    <div className="min-h-full pb-14">
      <IOSRedirectBanner />
      <Outlet />
      <TabBar />
    </div>
  );
}
