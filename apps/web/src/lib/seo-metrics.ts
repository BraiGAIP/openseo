/**
 * Estimated organic CTR by position. Mirrors public.ctr_for_position()
 * (migration 20260927120117) — keep both in sync.
 */
export function ctrForPosition(position: number | null | undefined): number {
  if (position == null || position < 1) return 0;
  const curve = [0.28, 0.15, 0.11, 0.08, 0.06, 0.05, 0.04, 0.03, 0.025, 0.02];
  if (position <= curve.length) return curve[position - 1];
  return position <= 20 ? 0.01 : 0;
}

/**
 * Rank movement as "places gained": positive = moved up (e.g. 8 → 5 is +3).
 * Entering the tracked depth counts from depth + 1; dropping out counts to depth + 1.
 */
export function positionChange(
  current: number | null | undefined,
  previous: number | null | undefined,
  depth = 100,
): number | null {
  if (current == null && previous == null) return null;
  const now = current ?? depth + 1;
  const before = previous ?? depth + 1;
  return before - now;
}

export type DifficultyLevel = "easy" | "moderate" | "hard" | "veryHard";

/** Keyword difficulty (0–100, DataForSEO Labs) bucketed for display. See docs/ARCHITECTURE.md §8.6. */
export function difficultyLevel(kd: number | null | undefined): DifficultyLevel | null {
  if (kd == null) return null;
  if (kd < 30) return "easy";
  if (kd < 50) return "moderate";
  if (kd < 70) return "hard";
  return "veryHard";
}

export type ChangeTone = "positive" | "negative" | "neutral";

const POSITIVE = new Set(["started_ranking", "entered_top3", "entered_top10", "position_up", "ai_overview_cited"]);
const NEGATIVE = new Set([
  "stopped_ranking",
  "left_top3",
  "left_top10",
  "position_down",
  "ai_overview_uncited",
  "competitor_entered",
]);

/** Whether a SERP change event is good or bad news for the tracked domain. */
export function changeTone(kind: string): ChangeTone {
  if (POSITIVE.has(kind)) return "positive";
  if (NEGATIVE.has(kind)) return "negative";
  return "neutral";
}

export const MAX_CHART_SERIES = 8;
export const SERIES_COLORS = Array.from({ length: MAX_CHART_SERIES }, (_, i) => `var(--series-${i + 1})`);

/**
 * Assigns each selected id a stable color slot: an id keeps its slot while it
 * stays selected, new ids take the lowest free slot (color follows the entity).
 */
export function assignSlots(previous: Map<string, number>, selected: string[]): Map<string, number> {
  const next = new Map<string, number>();
  for (const id of selected) {
    const slot = previous.get(id);
    if (slot !== undefined) next.set(id, slot);
  }
  const used = new Set(next.values());
  for (const id of selected) {
    if (next.has(id)) continue;
    let slot = 0;
    while (used.has(slot)) slot++;
    if (slot >= MAX_CHART_SERIES) break;
    next.set(id, slot);
    used.add(slot);
  }
  return next;
}
