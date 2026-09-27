import "server-only";
import { cache } from "react";
import type { PlanLimits } from "@openseo/shared";
import { createClient } from "@/lib/supabase/server";

export const getMemberships = cache(async () => {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("organization_members")
    .select("role, organizations!inner(id, name, slug, is_personal, created_at)")
    .order("created_at", { referencedTable: "organizations" });
  if (error) throw error;
  return data
    .map((m) => ({ role: m.role, ...m.organizations }))
    .sort((a, b) => Number(b.is_personal) - Number(a.is_personal) || a.created_at.localeCompare(b.created_at));
});

export const getOrganizationBySlug = cache(async (slug: string) => {
  const memberships = await getMemberships();
  return memberships.find((m) => m.slug === slug) ?? null;
});

export async function getOrganizationPlan(organizationId: string) {
  const supabase = await createClient();
  const { data } = await supabase
    .from("subscriptions")
    .select("status, plans(id, name, limits)")
    .eq("organization_id", organizationId)
    .in("status", ["trialing", "active", "past_due"])
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (data?.plans) {
    return { id: data.plans.id, name: data.plans.name, limits: data.plans.limits as unknown as PlanLimits };
  }
  const { data: free } = await supabase.from("plans").select("id, name, limits").eq("id", "free").single();
  return { id: "free", name: free?.name ?? "Free", limits: (free?.limits ?? {}) as unknown as PlanLimits };
}

export async function getUsageSummary(organizationId: string) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_usage_summary", { p_org_id: organizationId });
  if (error) throw error;
  return data;
}

export async function getProjects(organizationId: string) {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("projects")
    .select("id, name, domain, client_name, location_code, language_code, keyword_tracking(count)")
    .eq("organization_id", organizationId)
    .is("archived_at", null)
    .order("created_at");
  if (error) throw error;
  return data.map((p) => ({ ...p, keywordCount: p.keyword_tracking[0]?.count ?? 0 }));
}

export async function getProject(organizationId: string, projectId: string) {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("projects")
    .select("id, name, domain, root_url, client_name, location_code, language_code, default_device")
    .eq("organization_id", organizationId)
    .eq("id", projectId)
    .maybeSingle();
  if (error) throw error;
  return data;
}

export async function getKeywords(projectId: string) {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("keyword_tracking")
    .select(
      "id, keyword, device, location_code, search_volume, current_position, previous_position, best_position, current_url, last_check_date, depth, serp_features",
    )
    .eq("project_id", projectId)
    .order("created_at");
  if (error) throw error;
  return data;
}

export async function getRankSummary(projectId: string, days: number) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("project_rank_summary", { p_project_id: projectId, p_days: days });
  if (error) throw error;
  return data;
}

export async function getPositionHistory(projectId: string, keywordIds: string[], days: number) {
  if (keywordIds.length === 0) return [];
  const since = new Date(Date.now() - days * 86_400_000).toISOString().slice(0, 10);
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("keyword_positions")
    .select("keyword_id, check_date, position")
    .eq("project_id", projectId)
    .in("keyword_id", keywordIds)
    .gte("check_date", since)
    .order("check_date");
  if (error) throw error;
  return data;
}
