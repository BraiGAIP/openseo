"use client";

import { useLocale, useTranslations } from "next-intl";
import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { FormMessage } from "@/components/ui/form-message";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { requestMagicLink, type LoginState } from "./actions";

export function LoginForm({ next, callbackError }: { next?: string; callbackError?: boolean }) {
  const t = useTranslations("Login");
  const locale = useLocale();
  const [state, action, pending] = useActionState<LoginState, FormData>(requestMagicLink, {
    status: "idle",
  });

  const message =
    state.status === "invalid"
      ? t("invalidEmail")
      : state.status === "failed"
        ? t("failed")
        : state.status === "idle" && callbackError
          ? t("callbackFailed")
          : null;

  return (
    <form action={action} className="space-y-4">
      <input type="hidden" name="locale" value={locale} />
      {next && <input type="hidden" name="next" value={next} />}
      <div className="space-y-1.5">
        <Label htmlFor="email">{t("email")}</Label>
        <Input id="email" name="email" type="email" autoComplete="email" required />
      </div>
      <FormMessage message={message} />
      <FormMessage message={state.status === "sent" ? t("sent") : null} tone="success" />
      <Button type="submit" className="w-full" disabled={pending}>
        {t("submit")}
      </Button>
    </form>
  );
}
