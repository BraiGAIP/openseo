"use client";

import { SEARCH_LOCATIONS } from "@openseo/shared";
import { useLocale, useTranslations } from "next-intl";
import { useActionState } from "react";
import { createProject, type FormState } from "@/app/[locale]/app/actions";
import { Button } from "@/components/ui/button";
import { FormMessage } from "@/components/ui/form-message";
import { Input, Select } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useErrorMessage } from "./use-error-message";

export function NewProjectForm({ organizationId, orgSlug }: { organizationId: string; orgSlug: string }) {
  const t = useTranslations("App");
  const locale = useLocale();
  const errorMessage = useErrorMessage();
  const [state, action, pending] = useActionState<FormState, FormData>(createProject, {});
  const regions = new Intl.DisplayNames([locale], { type: "region" });
  const languages = new Intl.DisplayNames([locale], { type: "language" });

  return (
    <form action={action} className="space-y-4">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="orgSlug" value={orgSlug} />
      <input type="hidden" name="locale" value={locale} />
      <div className="space-y-1.5">
        <Label htmlFor="name">{t("projectName")}</Label>
        <Input id="name" name="name" required maxLength={120} />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="domain">{t("domain")}</Label>
        <Input id="domain" name="domain" required placeholder="example.com" aria-describedby="domain-hint" />
        <p id="domain-hint" className="text-xs text-muted-foreground">
          {t("domainHint")}
        </p>
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="location">{t("location")}</Label>
        <Select id="location" name="location" defaultValue={locale === "fi" ? 2246 : locale === "sv" ? 2752 : 2840}>
          {SEARCH_LOCATIONS.map((l) => (
            <option key={l.code} value={l.code}>
              {regions.of(l.country)} · {languages.of(l.language)}
            </option>
          ))}
        </Select>
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="clientName">{t("clientName")}</Label>
        <Input id="clientName" name="clientName" maxLength={120} />
      </div>
      <FormMessage message={errorMessage(state.error)} />
      <Button type="submit" disabled={pending}>
        {t("createProject")}
      </Button>
    </form>
  );
}
