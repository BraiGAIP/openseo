"use server";

import { SEARCH_LOCATIONS } from "@openseo/shared";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { getPositionHistory } from "@/lib/data";
import { isValidDomain, normalizeDomain } from "@/lib/domain";
import { toActionError, type ActionError } from "@/lib/errors";
import { createClient, getUserId } from "@/lib/supabase/server";

export type FormState = { ok?: true; count?: number; error?: ActionError };

const MAX_KEYWORDS_PER_SUBMIT = 500;

async function requireUser() {
  const userId = await getUserId();
  if (!userId) redirect("/login");
  return userId;
}

export async function signOut(locale: string) {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect(locale === "en" ? "/" : `/${locale}`);
}

const projectSchema = z.object({
  organizationId: z.uuid(),
  orgSlug: z.string().min(1),
  locale: z.string().min(2),
  name: z.string().trim().min(1).max(120),
  domain: z.string().trim().min(1),
  location: z.coerce.number().int(),
  clientName: z.string().trim().max(120).optional(),
});

export async function createProject(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireUser();
  const parsed = projectSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: { code: "required" } };

  const domain = normalizeDomain(parsed.data.domain);
  if (!isValidDomain(domain)) return { error: { code: "invalidDomain" } };
  const location = SEARCH_LOCATIONS.find((l) => l.code === parsed.data.location) ?? SEARCH_LOCATIONS[0];

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("projects")
    .insert({
      organization_id: parsed.data.organizationId,
      name: parsed.data.name,
      domain,
      root_url: `https://${domain}/`,
      location_code: location.code,
      language_code: location.language,
      client_name: parsed.data.clientName || null,
      is_client_project: Boolean(parsed.data.clientName),
    })
    .select("id")
    .single();
  if (error) return { error: toActionError(error) };

  const { locale, orgSlug } = parsed.data;
  revalidatePath(`/[locale]/app/[org]`, "page");
  redirect(`${locale === "en" ? "" : `/${locale}`}/app/${orgSlug}/projects/${data.id}`);
}

const keywordsSchema = z.object({
  projectId: z.uuid(),
  keywords: z.string(),
  device: z.enum(["desktop", "mobile"]),
});

export async function addKeywords(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireUser();
  const parsed = keywordsSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: { code: "required" } };

  const seen = new Set<string>();
  const keywords = parsed.data.keywords
    .split(/\r?\n/)
    .map((k) => k.trim().replace(/\s+/g, " "))
    .filter((k) => k.length > 0 && k.length <= 300)
    .filter((k) => !seen.has(k.toLowerCase()) && seen.add(k.toLowerCase()))
    .slice(0, MAX_KEYWORDS_PER_SUBMIT);
  if (keywords.length === 0) return { error: { code: "required" } };

  const supabase = await createClient();
  const { data: project, error: projectError } = await supabase
    .from("projects")
    .select("id, organization_id, location_code, language_code")
    .eq("id", parsed.data.projectId)
    .maybeSingle();
  if (projectError || !project) return { error: { code: "forbidden" } };

  const { data, error } = await supabase
    .from("keyword_tracking")
    .upsert(
      keywords.map((keyword) => ({
        project_id: project.id,
        organization_id: project.organization_id, // overwritten by trigger; required by the type
        keyword,
        device: parsed.data.device,
        location_code: project.location_code,
        language_code: project.language_code,
      })),
      {
        onConflict: "project_id,keyword_normalized,location_code,language_code,search_engine,device",
        ignoreDuplicates: true,
      },
    )
    .select("id");
  if (error) return { error: toActionError(error) };

  revalidatePath(`/[locale]/app/[org]/projects/[projectId]`, "page");
  return { ok: true, count: data.length };
}

export async function deleteKeyword(projectId: string, keywordId: string): Promise<FormState> {
  await requireUser();
  const supabase = await createClient();
  const { error } = await supabase
    .from("keyword_tracking")
    .delete()
    .eq("project_id", projectId)
    .eq("id", keywordId);
  if (error) return { error: toActionError(error) };
  revalidatePath(`/[locale]/app/[org]/projects/[projectId]`, "page");
  return { ok: true };
}

const historySchema = z.object({
  projectId: z.uuid(),
  keywordIds: z.array(z.uuid()).max(8),
  days: z.number().int().min(1).max(365),
});

export async function loadKeywordHistory(input: z.input<typeof historySchema>) {
  await requireUser();
  const { projectId, keywordIds, days } = historySchema.parse(input);
  return getPositionHistory(projectId, keywordIds, days);
}
