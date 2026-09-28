import "server-only";
import { createClient } from "@supabase/supabase-js";
import type { Database, PlanLimits, Tables } from "@openseo/shared";

export type PublicPlan = Omit<Tables<"plans">, "limits"> & { limits: PlanLimits };

/** Public plan catalogue (anon read). Returns [] when Supabase isn't configured. */
export async function getPublicPlans(): Promise<PublicPlan[]> {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) return [];
  const supabase = createClient<Database>(url, key, { auth: { persistSession: false } });
  const { data, error } = await supabase
    .from("plans")
    .select("*")
    .eq("is_public", true)
    .order("sort_order");
  if (error) return [];
  return data.map((plan) => ({ ...plan, limits: plan.limits as unknown as PlanLimits }));
}
