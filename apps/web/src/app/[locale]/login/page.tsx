import { getTranslations, setRequestLocale } from "next-intl/server";
import { SiteHeader } from "@/components/site/site-header";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { LoginForm } from "./login-form";

export default async function LoginPage({ params, searchParams }: PageProps<"/[locale]/login">) {
  const { locale } = await params;
  setRequestLocale(locale);
  const query = await searchParams;
  const t = await getTranslations("Login");
  const next = typeof query.next === "string" && /^\/(?!\/)/.test(query.next) ? query.next : undefined;

  return (
    <>
      <SiteHeader />
      <main className="flex flex-1 items-start justify-center px-4 py-16">
        <Card className="w-full max-w-sm">
          <CardHeader>
            <CardTitle className="text-xl">{t("title")}</CardTitle>
            <CardDescription>{t("description")}</CardDescription>
          </CardHeader>
          <CardContent>
            <LoginForm next={next} callbackError={query.error === "callback"} />
          </CardContent>
        </Card>
      </main>
    </>
  );
}
