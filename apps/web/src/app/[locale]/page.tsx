import { getFormatter, getTranslations, setRequestLocale } from "next-intl/server";
import { SiteHeader } from "@/components/site/site-header";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Link } from "@/i18n/navigation";
import { getPublicPlans } from "@/lib/plans";

const FEATURES = ["rank", "audit", "competitors", "reports"] as const;

export default async function LandingPage({ params }: PageProps<"/[locale]">) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations("Landing");
  const format = await getFormatter();
  const plans = await getPublicPlans();

  const limit = (key: "projects" | "keywords" | "seats" | "auditPages", count: number) =>
    count < 0 ? t(`limits.${key}Unlimited`) : t(`limits.${key}`, { count });

  return (
    <>
      <SiteHeader />
      <main className="flex-1">
        <section className="mx-auto max-w-6xl px-4 py-20">
          <p className="text-sm font-medium text-primary">{t("eyebrow")}</p>
          <h1 className="mt-3 max-w-3xl text-4xl font-semibold tracking-tight sm:text-5xl">{t("title")}</h1>
          <p className="mt-5 max-w-2xl text-lg text-muted-foreground">{t("subtitle")}</p>
          <div className="mt-8 flex flex-wrap gap-3">
            <Button asChild size="lg">
              <Link href="/login">{t("cta")}</Link>
            </Button>
            <Button asChild size="lg" variant="outline">
              <a href="#pricing">{t("secondaryCta")}</a>
            </Button>
          </div>
        </section>

        <section className="mx-auto max-w-6xl px-4 pb-16" aria-labelledby="features">
          <h2 id="features" className="text-2xl font-semibold tracking-tight">
            {t("featuresTitle")}
          </h2>
          <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {FEATURES.map((key) => (
              <Card key={key}>
                <CardHeader>
                  <CardTitle>{t(`features.${key}.title`)}</CardTitle>
                </CardHeader>
                <CardContent className="text-sm text-muted-foreground">{t(`features.${key}.body`)}</CardContent>
              </Card>
            ))}
          </div>
        </section>

        {plans.length > 0 && (
          <section id="pricing" className="mx-auto max-w-6xl px-4 pb-24" aria-labelledby="pricing-title">
            <h2 id="pricing-title" className="text-2xl font-semibold tracking-tight">
              {t("pricingTitle")}
            </h2>
            <p className="mt-2 text-sm text-muted-foreground">{t("pricingSubtitle")}</p>
            <div className="mt-6 grid gap-4 md:grid-cols-3">
              {plans.map((plan) => (
                <Card key={plan.id} className={plan.id === "pro" ? "border-primary" : undefined}>
                  <CardHeader>
                    <CardTitle>{plan.name}</CardTitle>
                    <p className="text-sm text-muted-foreground">{plan.description}</p>
                    <p className="mt-3 text-3xl font-semibold">
                      {format.number(plan.price_monthly_cents / 100, {
                        style: "currency",
                        currency: plan.currency.toUpperCase(),
                        maximumFractionDigits: 0,
                      })}
                      <span className="ml-1 text-sm font-normal text-muted-foreground">{t("perMonth")}</span>
                    </p>
                  </CardHeader>
                  <CardContent>
                    <ul className="space-y-1.5 text-sm">
                      <li>{limit("projects", plan.limits.max_projects)}</li>
                      <li>{limit("keywords", plan.limits.max_keywords)}</li>
                      <li>{limit("seats", plan.limits.max_seats)}</li>
                      <li>{limit("auditPages", plan.limits.quota.audit_page ?? 0)}</li>
                      {plan.limits.api_access && <li>{t("limits.api")}</li>}
                      {plan.limits.white_label && <li>{t("limits.whiteLabel")}</li>}
                    </ul>
                  </CardContent>
                </Card>
              ))}
            </div>
          </section>
        )}
      </main>
    </>
  );
}
