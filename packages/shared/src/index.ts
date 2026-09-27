export type { Database, Json } from "./database.types";
import type { Database } from "./database.types";

type PublicSchema = Database["public"];

/** Row type of a table in the `public` schema. */
export type Tables<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Row"];
/** Insert type of a table in the `public` schema. */
export type TablesInsert<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Insert"];
/** Enum type in the `public` schema. */
export type Enums<T extends keyof PublicSchema["Enums"]> = PublicSchema["Enums"][T];

export const LOCALES = ["en", "fi", "sv"] as const;
export type Locale = (typeof LOCALES)[number];
export const DEFAULT_LOCALE: Locale = "en";

/** Shape of `public.plans.limits` (see migration 0001). -1 = unlimited. */
export type PlanLimits = {
  max_projects: number;
  max_keywords: number;
  max_seats: number;
  max_competitors_per_project: number;
  max_pages_per_audit: number;
  rank_check_min_frequency: Enums<"check_frequency">;
  rank_depth: number;
  api_access: boolean;
  white_label: boolean;
  custom_domain: boolean;
  overage_enabled: boolean;
  quota: Partial<Record<Enums<"usage_metric">, number>>;
};

/** Common DataForSEO location codes offered in the UI. */
export const SEARCH_LOCATIONS = [
  { code: 2840, country: "US", language: "en" },
  { code: 2826, country: "GB", language: "en" },
  { code: 2124, country: "CA", language: "en" },
  { code: 2036, country: "AU", language: "en" },
  { code: 2276, country: "DE", language: "de" },
  { code: 2246, country: "FI", language: "fi" },
  { code: 2752, country: "SE", language: "sv" },
  { code: 2578, country: "NO", language: "no" },
  { code: 2208, country: "DK", language: "da" },
] as const;
