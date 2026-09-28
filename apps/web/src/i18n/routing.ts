import { defineRouting } from "next-intl/routing";
import { DEFAULT_LOCALE, LOCALES } from "@openseo/shared";

export const routing = defineRouting({
  locales: LOCALES,
  defaultLocale: DEFAULT_LOCALE,
  // English lives at "/", Finnish at "/fi", Swedish at "/sv".
  localePrefix: "as-needed",
});
