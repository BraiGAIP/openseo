import { getLocale, getTranslations } from "next-intl/server";
import { signOut } from "@/app/[locale]/app/actions";
import { LocaleSwitcher } from "@/components/site/locale-switcher";
import { Button } from "@/components/ui/button";
import { Link } from "@/i18n/navigation";
import { getMemberships } from "@/lib/data";
import { OrgSwitcher } from "./org-switcher";

export async function AppHeader() {
  const t = await getTranslations("Common");
  const locale = await getLocale();
  const memberships = await getMemberships();

  return (
    <header className="border-b border-border bg-surface">
      <div className="mx-auto flex h-14 max-w-7xl items-center justify-between gap-4 px-4">
        <div className="flex items-center gap-4">
          <Link href="/app" className="text-lg font-semibold tracking-tight">
            {t("appName")}
          </Link>
          <OrgSwitcher organizations={memberships} />
        </div>
        <div className="flex items-center gap-3">
          <LocaleSwitcher />
          <form action={signOut.bind(null, locale)}>
            <Button type="submit" variant="ghost" size="sm">
              {t("signOut")}
            </Button>
          </form>
        </div>
      </div>
    </header>
  );
}
