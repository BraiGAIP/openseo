import { getFormatter, getTranslations, setRequestLocale } from "next-intl/server";
import { notFound } from "next/navigation";
import { NewProjectForm } from "@/components/app/new-project-form";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Link } from "@/i18n/navigation";
import { getOrganizationBySlug, getOrganizationPlan, getProjects, getUsageSummary } from "@/lib/data";

export default async function OrganizationPage({ params }: PageProps<"/[locale]/app/[org]">) {
  const { locale, org: slug } = await params;
  setRequestLocale(locale);
  const org = await getOrganizationBySlug(slug);
  if (!org) notFound();

  const [t, format, projects, plan, usage] = await Promise.all([
    getTranslations("App"),
    getFormatter(),
    getProjects(org.id),
    getOrganizationPlan(org.id),
    getUsageSummary(org.id),
  ]);
  const canEdit = org.role === "admin" || org.role === "owner";

  return (
    <div className="grid gap-8 lg:grid-cols-[1fr_20rem]">
      <section aria-labelledby="projects-title">
        <h1 id="projects-title" className="text-2xl font-semibold tracking-tight">
          {org.name}
        </h1>
        <h2 className="mt-6 text-sm font-medium text-muted-foreground">{t("projects")}</h2>
        {projects.length === 0 ? (
          <p className="mt-3 text-sm text-muted-foreground">{t("noProjects")}</p>
        ) : (
          <ul className="mt-3 grid gap-3 sm:grid-cols-2">
            {projects.map((project) => (
              <li key={project.id}>
                <Link
                  href={`/app/${org.slug}/projects/${project.id}`}
                  className="block rounded-lg border border-border bg-surface p-4 transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                >
                  <p className="font-medium">{project.name}</p>
                  <p className="text-sm text-muted-foreground">{project.domain}</p>
                  <p className="mt-2 text-xs text-subtle-foreground">
                    {project.client_name ? `${project.client_name} · ` : ""}
                    {t("keywordsCount", { count: project.keywordCount })}
                  </p>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>

      <aside className="space-y-6">
        {canEdit && (
          <Card>
            <CardHeader>
              <CardTitle>{t("newProject")}</CardTitle>
            </CardHeader>
            <CardContent>
              <NewProjectForm organizationId={org.id} orgSlug={org.slug} />
            </CardContent>
          </Card>
        )}
        <Card>
          <CardHeader>
            <CardTitle>{t("usageTitle")}</CardTitle>
            <CardDescription>{t("plan", { plan: plan.name })}</CardDescription>
          </CardHeader>
          <CardContent>
            <table className="w-full text-sm">
              <tbody>
                {usage.map((row) => (
                  <tr key={row.metric} className="border-t border-border first:border-t-0">
                    <th scope="row" className="py-1.5 text-left font-normal text-muted-foreground">
                      {t(`metric.${row.metric}`)}
                    </th>
                    <td className="py-1.5 text-right tabular-nums">
                      {row.quota == null
                        ? t("usedUnlimited", { used: format.number(row.used) })
                        : t("usedOf", { used: format.number(row.used), quota: format.number(row.quota) })}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </CardContent>
        </Card>
      </aside>
    </div>
  );
}
