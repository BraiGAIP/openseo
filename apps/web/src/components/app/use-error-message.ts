"use client";

import { useTranslations } from "next-intl";
import type { ActionError } from "@/lib/errors";

export function useErrorMessage() {
  const t = useTranslations("Errors");
  return (error?: ActionError) => {
    if (!error) return null;
    return error.code === "planLimit" ? t("planLimit", { limit: error.limit }) : t(error.code);
  };
}
