"use client";

import { useFormatter, useTranslations } from "next-intl";
import { useMemo, useState, useTransition } from "react";
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
  type TooltipContentProps,
} from "recharts";
import { deleteKeyword, loadKeywordHistory } from "@/app/[locale]/app/actions";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { assignSlots, MAX_CHART_SERIES, positionChange, SERIES_COLORS } from "@/lib/seo-metrics";
import { cn } from "@/lib/utils";

export type KeywordRow = {
  id: string;
  keyword: string;
  device: string;
  search_volume: number | null;
  current_position: number | null;
  previous_position: number | null;
  best_position: number | null;
  current_url: string | null;
  last_check_date: string | null;
  depth: number;
};

export type HistoryRow = { keyword_id: string; check_date: string; position: number | null };

type Props = {
  projectId: string;
  days: number;
  keywords: KeywordRow[];
  initialSelection: string[];
  initialHistory: HistoryRow[];
  canEdit: boolean;
};

export function RankDashboard({ projectId, days, keywords, initialSelection, initialHistory, canEdit }: Props) {
  const t = useTranslations("Project");
  const format = useFormatter();
  const [slots, setSlots] = useState(() => assignSlots(new Map(), initialSelection));
  const [history, setHistory] = useState<HistoryRow[]>(initialHistory);
  const [loaded, setLoaded] = useState(() => new Set(initialSelection));
  const [limitHit, setLimitHit] = useState(false);
  const [pending, startTransition] = useTransition();

  const byId = useMemo(() => new Map(keywords.map((k) => [k.id, k])), [keywords]);
  const selected = [...slots.keys()].filter((id) => byId.has(id));

  function toggle(id: string) {
    const next = slots.has(id) ? selected.filter((s) => s !== id) : [...selected, id];
    if (next.length > MAX_CHART_SERIES) {
      setLimitHit(true);
      return;
    }
    setLimitHit(false);
    setSlots(assignSlots(slots, next));
    const missing = next.filter((k) => !loaded.has(k));
    if (missing.length > 0) {
      startTransition(async () => {
        const rows = await loadKeywordHistory({ projectId, keywordIds: missing, days });
        setHistory((h) => [...h, ...rows]);
        setLoaded((l) => new Set([...l, ...missing]));
      });
    }
  }

  const chartData = useMemo(() => {
    const rows = new Map<string, Record<string, number | string | null>>();
    for (const h of history) {
      if (!slots.has(h.keyword_id)) continue;
      const row = rows.get(h.check_date) ?? { date: h.check_date };
      row[h.keyword_id] = h.position;
      rows.set(h.check_date, row);
    }
    return [...rows.values()].sort((a, b) => String(a.date).localeCompare(String(b.date)));
  }, [history, slots]);

  const maxPosition = Math.max(10, ...history.filter((h) => slots.has(h.keyword_id)).map((h) => h.position ?? 0));
  const directLabels = selected.length <= 4;
  const shortDate = (value: string) => format.dateTime(new Date(`${value}T00:00:00`), { month: "short", day: "numeric" });

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>{t("chartTitle")}</CardTitle>
          <CardDescription>{t("chartHint")}</CardDescription>
        </CardHeader>
        <CardContent className={cn(pending && "opacity-60 transition-opacity")}>
          {chartData.length === 0 ? (
            <p className="py-16 text-center text-sm text-muted-foreground">{t("chartEmpty")}</p>
          ) : (
            <>
              <ul className="mb-3 flex flex-wrap gap-x-4 gap-y-1 text-sm" aria-label={t("keywordsTitle")}>
                {selected.map((id) => (
                  <li key={id} className="flex items-center gap-1.5 text-muted-foreground">
                    <span
                      aria-hidden
                      className="inline-block h-0.5 w-4 rounded-full"
                      style={{ background: SERIES_COLORS[slots.get(id)!] }}
                    />
                    {byId.get(id)?.keyword}
                  </li>
                ))}
              </ul>
              <div className="h-72 w-full">
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart data={chartData} margin={{ top: 8, right: directLabels ? 112 : 16, bottom: 4, left: 0 }}>
                    <CartesianGrid vertical={false} stroke="var(--chart-grid)" />
                    <XAxis
                      dataKey="date"
                      tickFormatter={shortDate}
                      stroke="var(--chart-axis)"
                      tick={{ fill: "var(--chart-muted)", fontSize: 12 }}
                      tickLine={false}
                      minTickGap={24}
                    />
                    <YAxis
                      reversed
                      domain={[1, maxPosition]}
                      allowDecimals={false}
                      width={36}
                      stroke="var(--chart-axis)"
                      tick={{ fill: "var(--chart-muted)", fontSize: 12 }}
                      tickLine={false}
                      axisLine={false}
                      label={{ value: t("positionAxis"), angle: -90, position: "insideLeft", fill: "var(--chart-muted)", fontSize: 12 }}
                    />
                    <Tooltip
                      cursor={{ stroke: "var(--chart-axis)", strokeWidth: 1 }}
                      content={(props) => (
                        <ChartTooltip {...props} byId={byId} slots={slots} formatDate={shortDate} depthLabel={t} />
                      )}
                    />
                    {selected.map((id) => {
                      const lastIndex = chartData.findLastIndex((row) => row[id] != null);
                      return (
                        <Line
                          key={id}
                          dataKey={id}
                          name={byId.get(id)?.keyword}
                          type="monotone"
                          stroke={SERIES_COLORS[slots.get(id)!]}
                          strokeWidth={2}
                          dot={false}
                          activeDot={{ r: 4, stroke: "var(--surface)", strokeWidth: 2 }}
                          connectNulls={false}
                          isAnimationActive={false}
                          label={
                            directLabels
                              ? ({ x, y, index }: { x?: number | string; y?: number | string; index?: number }) =>
                                  index === lastIndex ? (
                                    <text
                                      key={`${id}-label`}
                                      x={Number(x) + 8}
                                      y={Number(y)}
                                      dy={4}
                                      fontSize={12}
                                      fill="var(--muted-foreground)"
                                    >
                                      {truncate(byId.get(id)?.keyword ?? "", 14)}
                                    </text>
                                  ) : null
                              : undefined
                          }
                        />
                      );
                    })}
                  </LineChart>
                </ResponsiveContainer>
              </div>
            </>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t("keywordsTitle")}</CardTitle>
          {limitHit && (
            <p role="status" className="text-sm text-danger-text">
              {t("selectLimit")}
            </p>
          )}
        </CardHeader>
        <CardContent className="overflow-x-auto">
          {keywords.length === 0 ? (
            <p className="text-sm text-muted-foreground">{t("noKeywords")}</p>
          ) : (
            <table className="w-full min-w-[48rem] text-sm">
              <thead>
                <tr className="border-b border-border text-left text-muted-foreground">
                  <th scope="col" className="w-10 py-2 font-normal">
                    <span className="sr-only">{t("col.select")}</span>
                  </th>
                  <th scope="col" className="py-2 font-normal">{t("col.keyword")}</th>
                  <th scope="col" className="py-2 text-right font-normal">{t("col.position")}</th>
                  <th scope="col" className="py-2 text-right font-normal">{t("col.change")}</th>
                  <th scope="col" className="py-2 text-right font-normal">{t("col.best")}</th>
                  <th scope="col" className="py-2 text-right font-normal">{t("col.volume")}</th>
                  <th scope="col" className="py-2 pl-4 font-normal">{t("col.url")}</th>
                  <th scope="col" className="py-2 font-normal">{t("col.checked")}</th>
                  {canEdit && <th scope="col" className="w-10 py-2" />}
                </tr>
              </thead>
              <tbody>
                {keywords.map((k) => {
                  const slot = slots.get(k.id);
                  const change = k.last_check_date ? positionChange(k.current_position, k.previous_position, k.depth) : null;
                  return (
                    <tr key={k.id} className="border-b border-border last:border-0">
                      <td className="py-2">
                        <label className="flex items-center gap-2">
                          <input
                            type="checkbox"
                            className="size-4 accent-[var(--primary)]"
                            checked={slot !== undefined}
                            onChange={() => toggle(k.id)}
                            aria-label={`${t("col.select")}: ${k.keyword}`}
                          />
                          {slot !== undefined && (
                            <span
                              aria-hidden
                              className="inline-block h-0.5 w-3 rounded-full"
                              style={{ background: SERIES_COLORS[slot] }}
                            />
                          )}
                        </label>
                      </td>
                      <td className="py-2 font-medium">
                        {k.keyword}
                        {k.device === "mobile" && (
                          <span className="ml-2 text-xs font-normal text-subtle-foreground">{t("mobile")}</span>
                        )}
                      </td>
                      <td className="py-2 text-right tabular-nums">
                        {!k.last_check_date ? (
                          <span className="text-subtle-foreground">{t("notChecked")}</span>
                        ) : k.current_position == null ? (
                          <span className="text-subtle-foreground">{t("notRanking", { depth: k.depth })}</span>
                        ) : (
                          k.current_position
                        )}
                      </td>
                      <td className="py-2 text-right tabular-nums">
                        <PositionChange change={change} />
                      </td>
                      <td className="py-2 text-right tabular-nums">{k.best_position ?? "—"}</td>
                      <td className="py-2 text-right tabular-nums">
                        {k.search_volume != null ? format.number(k.search_volume) : "—"}
                      </td>
                      <td className="max-w-64 truncate py-2 pl-4">
                        {k.current_url ? (
                          <a href={k.current_url} target="_blank" rel="noreferrer noopener" className="text-primary hover:underline">
                            {k.current_url.replace(/^https?:\/\//, "")}
                          </a>
                        ) : (
                          "—"
                        )}
                      </td>
                      <td className="py-2 tabular-nums text-muted-foreground">
                        {k.last_check_date ? shortDate(k.last_check_date) : "—"}
                      </td>
                      {canEdit && (
                        <td className="py-2 text-right">
                          <button
                            type="button"
                            className="rounded px-2 py-1 text-subtle-foreground hover:bg-accent hover:text-foreground"
                            aria-label={`${t("remove")}: ${k.keyword}`}
                            onClick={() => {
                              if (window.confirm(`${t("remove")}: ${k.keyword}?`)) {
                                startTransition(async () => {
                                  await deleteKeyword(projectId, k.id);
                                });
                              }
                            }}
                          >
                            ×
                          </button>
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

function PositionChange({ change }: { change: number | null }) {
  const t = useTranslations("Project");
  if (change == null || change === 0) {
    return (
      <span className="text-subtle-foreground">
        <span aria-hidden>–</span>
        <span className="sr-only">{t("unchanged")}</span>
      </span>
    );
  }
  const up = change > 0;
  return (
    <span className={up ? "text-success-text" : "text-danger-text"}>
      <span aria-hidden>
        {up ? "▲" : "▼"} {Math.abs(change)}
      </span>
      <span className="sr-only">{up ? t("improved", { count: change }) : t("declined", { count: -change })}</span>
    </span>
  );
}

function ChartTooltip({
  active,
  payload,
  label,
  byId,
  slots,
  formatDate,
  depthLabel,
}: TooltipContentProps & {
  byId: Map<string, KeywordRow>;
  slots: Map<string, number>;
  formatDate: (value: string) => string;
  depthLabel: ReturnType<typeof useTranslations<"Project">>;
}) {
  if (!active || !payload?.length) return null;
  const rows = [...payload].sort((a, b) => (Number(a.value) || 999) - (Number(b.value) || 999));
  return (
    <div className="rounded-md border border-border bg-surface px-3 py-2 text-xs shadow-sm">
      <p className="mb-1 font-medium">{formatDate(String(label))}</p>
      <ul className="space-y-0.5">
        {rows.map((row) => {
          const id = String(row.dataKey);
          const keyword = byId.get(id);
          return (
            <li key={id} className="flex items-center gap-2">
              <span aria-hidden className="inline-block h-0.5 w-3 rounded-full" style={{ background: SERIES_COLORS[slots.get(id) ?? 0] }} />
              <span className="text-muted-foreground">{keyword?.keyword}</span>
              <span className="ml-auto pl-3 font-medium tabular-nums">
                {row.value ?? depthLabel("notRanking", { depth: keyword?.depth ?? 100 })}
              </span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

function truncate(text: string, max: number) {
  return text.length > max ? `${text.slice(0, max - 1)}…` : text;
}
