import { getFormatter, getTranslations } from "next-intl/server";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { changeTone, type ChangeTone } from "@/lib/seo-metrics";
import { cn } from "@/lib/utils";

export type ChangeEvent = {
  id: number;
  check_date: string;
  kind: string;
  subject: string;
  payload: unknown;
  keyword: string;
};

const TONE_MARK: Record<ChangeTone, { mark: string; className: string }> = {
  positive: { mark: "▲", className: "text-success-text" },
  negative: { mark: "▼", className: "text-danger-text" },
  neutral: { mark: "•", className: "text-subtle-foreground" },
};

function num(payload: unknown, key: string): number {
  const value = (payload as Record<string, unknown> | null)?.[key];
  return typeof value === "number" ? value : 0;
}

/** What changed in the SERPs since each keyword's previous check (worker: rank/changes.py). */
export async function SerpChanges({ events }: { events: ChangeEvent[] }) {
  const [t, format] = await Promise.all([getTranslations("Changes"), getFormatter()]);

  function describe(e: ChangeEvent): string {
    const values = {
      from: num(e.payload, "from"),
      to: num(e.payload, "to"),
      delta: Math.abs(num(e.payload, "delta")),
      rank: num(e.payload, "rank"),
      previousRank: num(e.payload, "previous_rank"),
      feature: e.subject,
      raw: e.subject.replaceAll("_", " "),
      domain: e.subject,
      url: e.subject.replace(/^https?:\/\//, ""),
    };
    return t.has(`kind.${e.kind}`) ? t(`kind.${e.kind}`, values) : e.kind;
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("title")}</CardTitle>
        <CardDescription>{t("hint")}</CardDescription>
      </CardHeader>
      <CardContent>
        {events.length === 0 ? (
          <p className="text-sm text-muted-foreground">{t("empty")}</p>
        ) : (
          <ol className="space-y-3 text-sm">
            {events.map((e) => {
              const tone = TONE_MARK[changeTone(e.kind)];
              return (
                <li key={e.id} className="flex gap-2.5">
                  <span aria-hidden className={cn("mt-0.5 w-3 shrink-0 text-xs", tone.className)}>
                    {tone.mark}
                  </span>
                  <div className="min-w-0">
                    <p className="truncate font-medium">{e.keyword}</p>
                    <p className="break-words text-muted-foreground">{describe(e)}</p>
                    <p className="text-xs text-subtle-foreground">
                      {format.dateTime(new Date(`${e.check_date}T00:00:00`), { dateStyle: "medium" })}
                    </p>
                  </div>
                </li>
              );
            })}
          </ol>
        )}
      </CardContent>
    </Card>
  );
}
