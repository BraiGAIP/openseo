import { getTranslations, setRequestLocale } from "next-intl/server";
import { notFound } from "next/navigation";
import { AddKeywordsForm } from "@/components/rank/add-keywords-form";
import { CheckNowButton } from "@/components/rank/check-now-button";
import { DemoDataNotice } from "@/components/rank/demo-data-notice";
import { RankDashboard } from "@/components/rank/rank-dashboard";
import { StatTiles } from "@/components/rank/stat-tiles";
import { Card, CardContent } from "@/components/ui/card";
import { Link } from "@/i18n/navigation";
import {
  getKeywords,
  getOrganizationBySlug,
  getPositionHistory,
  getProject,
  getRankCheckStatus,
  getRankSummary,
} from "@/lib/data";
import { cn } from "@/lib/utils";

const RANGES = [7, 30, 90] as const;
const DEFAULT_SELECTION = 5;

export default async function ProjectPage({
  params,
  searchParams,
}: PageProps<"/[locale]/app/[org]/projects/[projectId]">) {
  const { locale, org: slug, projectId } = await params;
  setRequestLocale(locale);
  const query = await searchParams;
  const days = RANGES.find((r) => String(r) === query.range) ?? 30;

  const org = await getOrganizationBySlug(slug);
  if (!org) notFound();
  const project = await getProject(org.id, projectId);
  if (!project) notFound();

  const [t, keywords, summary, checkStatus] = await Promise.all([
    getTranslations("Project"),
    getKeywords(project.id),
    getRankSummary(project.id, days),
    getRankCheckStatus(project.id),
  ]);
  const showsDemoData = keywords.some((k) => k.last_provider === "mock");

  // Default chart selection: best-ranking keywords first, then the rest in table order.
  const initialSelection = [...keywords]
    .sort((a, b) => (a.current_position ?? 999) - (b.current_position ?? 999))
    .slice(0, DEFAULT_SELECTION)
    .map((k) => k.id);
  const initialHistory = await getPositionHistory(
    project.id,
    initialSelection,
    days,
  );
  const canEdit = org.role === "admin" || org.role === "owner";

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <Link
            href={`/app/${org.slug}`}
            className="text-sm text-muted-foreground hover:text-foreground"
          >
            ← {t("back")}
          </Link>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight">
            {project.name}
          </h1>
          <p className="text-sm text-muted-foreground">
            {project.domain}
            {project.client_name ? ` · ${project.client_name}` : ""}
          </p>
        </div>
        <div className="flex flex-wrap items-start gap-3">
          {canEdit && (
            <CheckNowButton
              projectId={project.id}
              running={checkStatus.running}
              availableAt={checkStatus.availableAt}
              hasKeywords={keywords.length > 0}
            />
          )}
          <nav
            aria-label={t("range")}
            className="flex rounded-md border border-border bg-surface p-0.5 text-sm"
          >
            {RANGES.map((range) => (
              <Link
                key={range}
                href={{
                  pathname: `/app/${org.slug}/projects/${project.id}`,
                  query: { range },
                }}
                aria-current={range === days ? "page" : undefined}
                className={cn(
                  "rounded px-3 py-1 text-muted-foreground",
                  range === days && "bg-accent font-medium text-foreground",
                )}
              >
                {t("rangeDays", { days: range })}
              </Link>
            ))}
          </nav>
        </div>
      </div>

      {showsDemoData && <DemoDataNotice />}

      <StatTiles tracked={keywords.length} summary={summary} />

      <div className="grid gap-6 xl:grid-cols-[1fr_20rem]">
        <RankDashboard
          key={days}
          projectId={project.id}
          days={days}
          keywords={keywords}
          initialSelection={initialSelection}
          initialHistory={initialHistory}
          canEdit={canEdit}
        />
        {canEdit && (
          <Card className="h-fit">
            <CardContent className="pt-5">
              <AddKeywordsForm
                projectId={project.id}
                defaultDevice={project.default_device}
              />
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}
