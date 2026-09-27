import { getFormatter, getTranslations } from "next-intl/server";
import { cn } from "@/lib/utils";

type Summary = {
  check_date: string;
  avg_position: number | null;
  top3: number;
  top10: number;
  visibility: number | null;
}[];

type Tile = {
  label: string;
  value: string;
  /** Signed change vs start of period; `higherIsBetter` decides good/bad. */
  delta?: { value: number; text: string; higherIsBetter: boolean };
};

export async function StatTiles({ tracked, summary }: { tracked: number; summary: Summary }) {
  const t = await getTranslations("Project.kpi");
  const format = await getFormatter();
  const latest = summary.at(-1);
  const first = summary.length > 1 ? summary[0] : undefined;
  const dash = "—";

  const delta = (now: number | null | undefined, before: number | null | undefined, higherIsBetter: boolean, digits = 0) => {
    if (now == null || before == null) return undefined;
    const value = Number((now - before).toFixed(digits));
    return {
      value,
      higherIsBetter,
      text: format.number(value, { signDisplay: "exceptZero", maximumFractionDigits: digits }),
    };
  };

  const tiles: Tile[] = [
    { label: t("tracked"), value: format.number(tracked) },
    {
      label: t("avgPosition"),
      value: latest?.avg_position != null ? format.number(latest.avg_position, { maximumFractionDigits: 1 }) : dash,
      delta: delta(latest?.avg_position, first?.avg_position, false, 1),
    },
    { label: t("top3"), value: latest ? format.number(latest.top3) : dash, delta: delta(latest?.top3, first?.top3, true) },
    { label: t("top10"), value: latest ? format.number(latest.top10) : dash, delta: delta(latest?.top10, first?.top10, true) },
    {
      label: t("visibility"),
      value: latest?.visibility != null ? `${format.number(latest.visibility, { maximumFractionDigits: 1 })} %` : dash,
      delta: delta(latest?.visibility, first?.visibility, true, 1),
    },
  ];

  return (
    <dl className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
      {tiles.map((tile) => {
        const good = tile.delta && tile.delta.value !== 0 && tile.delta.value > 0 === tile.delta.higherIsBetter;
        const bad = tile.delta && tile.delta.value !== 0 && !good;
        return (
          <div key={tile.label} className="rounded-lg border border-border bg-surface p-4">
            <dt className="text-sm text-muted-foreground">{tile.label}</dt>
            <dd className="mt-1 text-2xl font-semibold">{tile.value}</dd>
            {tile.delta && tile.delta.value !== 0 && (
              <dd className={cn("mt-1 text-xs", good && "text-success-text", bad && "text-danger-text")}>
                <span aria-hidden>{good ? "▲" : "▼"}</span> {tile.delta.text}{" "}
                <span className="text-subtle-foreground">{t("vsStart")}</span>
              </dd>
            )}
          </div>
        );
      })}
    </dl>
  );
}
