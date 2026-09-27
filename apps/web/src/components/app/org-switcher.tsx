"use client";

import { useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { useRouter } from "@/i18n/navigation";

type Org = { slug: string; name: string; is_personal: boolean };

export function OrgSwitcher({ organizations }: { organizations: Org[] }) {
  const t = useTranslations("App");
  const router = useRouter();
  const params = useParams<{ org?: string }>();

  return (
    <select
      aria-label={t("workspaces")}
      className="h-8 max-w-56 rounded-md border border-input bg-surface px-2 text-sm"
      value={params.org ?? ""}
      onChange={(event) => router.push(`/app/${event.target.value}`)}
    >
      {!params.org && <option value="">{t("workspaces")}</option>}
      {organizations.map((org) => (
        <option key={org.slug} value={org.slug}>
          {org.is_personal ? `${org.name} (${t("personal")})` : org.name}
        </option>
      ))}
    </select>
  );
}
