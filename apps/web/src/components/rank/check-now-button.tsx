"use client";

import { useFormatter, useTranslations } from "next-intl";
import { useEffect, useState, useTransition } from "react";
import { requestRankCheck, type FormState } from "@/app/[locale]/app/actions";
import { useErrorMessage } from "@/components/app/use-error-message";
import { Button } from "@/components/ui/button";
import { FormMessage } from "@/components/ui/form-message";
import { useRouter } from "@/i18n/navigation";

const POLL_MS = 5_000;
const MAX_POLLS = 120; // stop auto-refreshing after ~10 minutes

export function CheckNowButton({
  projectId,
  running,
  availableAt,
  hasKeywords,
}: {
  projectId: string;
  running: boolean;
  availableAt: string | null;
  hasKeywords: boolean;
}) {
  const t = useTranslations("Project");
  const format = useFormatter();
  const errorMessage = useErrorMessage();
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [state, setState] = useState<FormState>({});

  // While a check is queued or running, refresh the server data until it finishes.
  useEffect(() => {
    if (!running) return;
    let polls = 0;
    const id = setInterval(() => {
      polls += 1;
      if (polls > MAX_POLLS) clearInterval(id);
      else router.refresh();
    }, POLL_MS);
    return () => clearInterval(id);
  }, [running, router]);

  const coolingDown = !running && availableAt !== null;
  const disabled = pending || running || coolingDown || !hasKeywords;

  return (
    <div className="flex flex-col items-end gap-1">
      <Button
        variant="outline"
        size="sm"
        disabled={disabled}
        aria-busy={running || pending}
        onClick={() =>
          startTransition(async () => {
            const result = await requestRankCheck(projectId);
            setState(result);
            if (result.ok) router.refresh();
          })
        }
      >
        <svg
          aria-hidden="true"
          viewBox="0 0 16 16"
          className={running || pending ? "size-3.5 animate-spin" : "size-3.5"}
          fill="none"
          stroke="currentColor"
          strokeWidth="1.6"
          strokeLinecap="round"
        >
          <path d="M13.5 8a5.5 5.5 0 1 1-1.6-3.9M13.5 2.5v2.8h-2.8" />
        </svg>
        {running ? t("checking") : t("checkNow")}
      </Button>
      <div aria-live="polite" className="text-right text-xs">
        {running ? (
          <p className="text-muted-foreground">{t("checkingHint")}</p>
        ) : coolingDown ? (
          <p className="text-muted-foreground">
            {t("checkAvailableAt", { time: format.dateTime(new Date(availableAt), { timeStyle: "short" }) })}
          </p>
        ) : state.ok ? (
          <FormMessage message={t("checkQueued", { count: state.count ?? 0 })} tone="success" />
        ) : (
          <FormMessage message={errorMessage(state.error)} />
        )}
      </div>
    </div>
  );
}
