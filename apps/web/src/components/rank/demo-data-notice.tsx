import { getTranslations } from "next-intl/server";

/** Shown when the latest positions come from the mock provider (no SERP provider configured). */
export async function DemoDataNotice() {
  const t = await getTranslations("Project");
  return (
    <div
      role="note"
      className="flex gap-3 rounded-md border border-warning-border bg-warning-surface px-4 py-3 text-sm text-warning-text"
    >
      <span className="mt-0.5 h-fit shrink-0 rounded border border-current px-1.5 text-[11px] font-semibold uppercase tracking-wide">
        {t("demoBadge")}
      </span>
      <p>{t("demoNotice")}</p>
    </div>
  );
}
