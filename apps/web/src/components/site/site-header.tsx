import { getTranslations } from "next-intl/server";
import { Button } from "@/components/ui/button";
import { Link } from "@/i18n/navigation";
import { getUserId } from "@/lib/supabase/server";
import { LocaleSwitcher } from "./locale-switcher";

export async function SiteHeader() {
  const t = await getTranslations("Common");
  const userId = await getUserId().catch(() => null);

  return (
    <header className="border-b border-border bg-surface">
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between gap-4 px-4">
        <Link href="/" className="text-lg font-semibold tracking-tight">
          {t("appName")}
        </Link>
        <nav className="flex items-center gap-3">
          <LocaleSwitcher />
          <Button asChild size="sm" variant={userId ? "default" : "outline"}>
            <Link href={userId ? "/app" : "/login"}>{userId ? t("openApp") : t("signIn")}</Link>
          </Button>
        </nav>
      </div>
    </header>
  );
}
