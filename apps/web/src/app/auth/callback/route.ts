import type { EmailOtpType } from "@supabase/supabase-js";
import { NextResponse, type NextRequest } from "next/server";
import { env } from "@/lib/env";
import { createClient } from "@/lib/supabase/server";

/** Magic-link landing: exchanges the PKCE code (or token hash) for a session. */
export async function GET(request: NextRequest) {
  const { searchParams } = request.nextUrl;
  // Redirect to the public site URL: behind Fly's proxy request.nextUrl.origin is the
  // container's own bind address (http://0.0.0.0:3000), which the browser can't reach.
  const origin = new URL(env.siteUrl).origin;
  const rawNext = searchParams.get("next") ?? "/app";
  const next = /^\/(?!\/)/.test(rawNext) ? rawNext : "/app";

  const supabase = await createClient();
  const code = searchParams.get("code");
  const tokenHash = searchParams.get("token_hash");
  const type = searchParams.get("type") as EmailOtpType | null;

  const { error } = code
    ? await supabase.auth.exchangeCodeForSession(code)
    : tokenHash && type
      ? await supabase.auth.verifyOtp({ token_hash: tokenHash, type })
      : { error: new Error("missing code") };

  if (error) {
    return NextResponse.redirect(new URL("/login?error=callback", origin));
  }
  return NextResponse.redirect(new URL(next, origin));
}
