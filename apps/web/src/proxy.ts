import createIntlMiddleware from "next-intl/middleware";
import { NextResponse, type NextRequest } from "next/server";
import { routing } from "@/i18n/routing";
import { refreshSession } from "@/lib/supabase/proxy";

const handleI18nRouting = createIntlMiddleware(routing);
const localePrefix = new RegExp(`^/(${routing.locales.join("|")})(?=/|$)`);

export async function proxy(request: NextRequest) {
  const response = handleI18nRouting(request);
  const userId = await refreshSession(request, response);

  const { pathname } = request.nextUrl;
  const locale = pathname.match(localePrefix)?.[1];
  const path = locale ? pathname.slice(locale.length + 1) || "/" : pathname;

  if (!userId && (path === "/app" || path.startsWith("/app/"))) {
    const login = request.nextUrl.clone();
    login.pathname = `${locale ? `/${locale}` : ""}/login`;
    login.search = `?next=${encodeURIComponent(pathname)}`;
    const redirect = NextResponse.redirect(login);
    response.cookies.getAll().forEach((cookie) => redirect.cookies.set(cookie));
    return redirect;
  }
  return response;
}

export const config = {
  // Skip API routes, the auth callback, Next internals and files with an extension.
  matcher: ["/((?!api|auth|_next|_vercel|.*\\..*).*)"],
};
