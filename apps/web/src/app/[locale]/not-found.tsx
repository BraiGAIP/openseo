import { useTranslations } from "next-intl";
import { Link } from "@/i18n/navigation";

export default function NotFound() {
  const t = useTranslations("Common");
  return (
    <main className="mx-auto flex max-w-md flex-1 flex-col items-center justify-center gap-4 px-4 py-24 text-center">
      <p className="text-5xl font-semibold">404</p>
      <Link href="/" className="text-primary hover:underline">
        {t("appName")}
      </Link>
    </main>
  );
}
