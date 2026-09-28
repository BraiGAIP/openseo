export type ActionError =
  | { code: "planLimit"; limit: string }
  | { code: "quotaExceeded"; metric: string }
  | {
      code: "invalidDomain" | "duplicate" | "required" | "forbidden" | "cooldown" | "noKeywords" | "generic";
    };

/** Maps a PostgREST/Postgres error to a translatable UI error code. */
export function toActionError(error: { code?: string; message?: string } | null | undefined): ActionError {
  const message = error?.message ?? "";
  const limit = message.match(/plan_limit_exceeded:(\w+)/)?.[1];
  if (limit) return { code: "planLimit", limit };
  const metric = message.match(/quota_exceeded:(\w+)/)?.[1];
  if (metric) return { code: "quotaExceeded", metric };
  if (/rank_check_cooldown/.test(message)) return { code: "cooldown" };
  if (/no_keywords/.test(message)) return { code: "noKeywords" };
  if (error?.code === "23505") return { code: "duplicate" };
  if (error?.code === "42501" || /row-level security/i.test(message)) return { code: "forbidden" };
  if (error?.code === "23514" && /domain/.test(message)) return { code: "invalidDomain" };
  return { code: "generic" };
}
