import { setRequestLocale } from "next-intl/server";
import { AppHeader } from "@/components/app/app-header";
import { redirect } from "@/i18n/navigation";
import { getUserId } from "@/lib/supabase/server";

export default async function AppLayout({ children, params }: LayoutProps<"/[locale]/app">) {
  const { locale } = await params;
  setRequestLocale(locale);
  if (!(await getUserId())) redirect({ href: "/login", locale });

  return (
    <>
      <AppHeader />
      <main className="mx-auto w-full max-w-7xl flex-1 px-4 py-8">{children}</main>
    </>
  );
}
