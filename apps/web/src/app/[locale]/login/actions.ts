"use server";

import { z } from "zod";
import { env } from "@/lib/env";
import { createClient } from "@/lib/supabase/server";

export type LoginState = { status: "idle" | "sent" | "invalid" | "failed" };

const schema = z.object({
  email: z.email(),
  next: z.string().regex(/^\/(?!\/)/).optional().catch(undefined),
  locale: z.string().optional(),
});

export async function requestMagicLink(_prev: LoginState, formData: FormData): Promise<LoginState> {
  const parsed = schema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { status: "invalid" };

  const callback = new URL("/auth/callback", env.siteUrl);
  callback.searchParams.set("next", parsed.data.next ?? `/${parsed.data.locale ?? "en"}/app`);

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithOtp({
    email: parsed.data.email,
    options: { emailRedirectTo: callback.toString(), shouldCreateUser: true },
  });
  return { status: error ? "failed" : "sent" };
}
