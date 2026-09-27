export type ActionError =
  | { code: "planLimit"; limit: string }
  | { code: "invalidDomain" | "duplicate" | "required" | "forbidden" | "generic" };

/** Maps a PostgREST/Postgres error to a translatable UI error code. */
export function toActionError(error: { code?: string; message?: string } | null | undefined): ActionError {
  const message = error?.message ?? "";
  const limit = message.match(/plan_limit_exceeded:(\w+)/)?.[1];
  if (limit) return { code: "planLimit", limit };
  if (error?.code === "23505") return { code: "duplicate" };
  if (error?.code === "42501" || /row-level security/i.test(message)) return { code: "forbidden" };
  if (error?.code === "23514" && /domain/.test(message)) return { code: "invalidDomain" };
  return { code: "generic" };
}
