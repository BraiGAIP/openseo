"use client";

import { useTranslations } from "next-intl";
import type { ActionError } from "@/lib/errors";

export function useErrorMessage() {
  const t = useTranslations("Errors");
  return (error?: ActionError) => {
    if (!error) return null;
    if (error.code === "planLimit") return t("planLimit", { limit: error.limit });
    if (error.code === "quotaExceeded") return t("quotaExceeded", { metric: error.metric });
    return t(error.code);
  };
}
