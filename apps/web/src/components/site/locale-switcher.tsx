"use client";

import { useLocale, useTranslations } from "next-intl";
import { useTransition } from "react";
import { usePathname, useRouter } from "@/i18n/navigation";
import { routing } from "@/i18n/routing";

const LABELS: Record<string, string> = { en: "English", fi: "Suomi", sv: "Svenska" };

export function LocaleSwitcher() {
  const t = useTranslations("Common");
  const locale = useLocale();
  const router = useRouter();
  const pathname = usePathname();
  const [pending, startTransition] = useTransition();

  return (
    <label className="flex items-center gap-2 text-sm text-muted-foreground">
      <span className="sr-only">{t("language")}</span>
      <select
        aria-label={t("language")}
        className="h-8 rounded-md border border-input bg-surface px-2 text-sm text-foreground"
        value={locale}
        disabled={pending}
        onChange={(event) =>
          startTransition(() => router.replace(pathname, { locale: event.target.value }))
        }
      >
        {routing.locales.map((l) => (
          <option key={l} value={l}>
            {LABELS[l]}
          </option>
        ))}
      </select>
    </label>
  );
}
