"use client";

import { useTranslations } from "next-intl";
import { useActionState, useEffect, useRef } from "react";
import { addKeywords, type FormState } from "@/app/[locale]/app/actions";
import { useErrorMessage } from "@/components/app/use-error-message";
import { Button } from "@/components/ui/button";
import { FormMessage } from "@/components/ui/form-message";
import { Select, Textarea } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export function AddKeywordsForm({ projectId, defaultDevice }: { projectId: string; defaultDevice: string }) {
  const t = useTranslations("Project");
  const errorMessage = useErrorMessage();
  const [state, action, pending] = useActionState<FormState, FormData>(addKeywords, {});
  const formRef = useRef<HTMLFormElement>(null);

  useEffect(() => {
    if (state.ok) formRef.current?.reset();
  }, [state]);

  return (
    <form ref={formRef} action={action} className="space-y-3">
      <input type="hidden" name="projectId" value={projectId} />
      <div className="space-y-1.5">
        <Label htmlFor="keywords">{t("addKeywords")}</Label>
        <Textarea id="keywords" name="keywords" required placeholder={t("keywordsPlaceholder")} rows={5} />
      </div>
      <div className="flex items-end gap-3">
        <div className="flex-1 space-y-1.5">
          <Label htmlFor="device">{t("device")}</Label>
          <Select id="device" name="device" defaultValue={defaultDevice}>
            <option value="desktop">{t("desktop")}</option>
            <option value="mobile">{t("mobile")}</option>
          </Select>
        </div>
        <Button type="submit" disabled={pending}>
          {t("add")}
        </Button>
      </div>
      <FormMessage message={errorMessage(state.error)} />
      <FormMessage message={state.ok ? t("added", { count: state.count ?? 0 }) : null} tone="success" />
    </form>
  );
}
