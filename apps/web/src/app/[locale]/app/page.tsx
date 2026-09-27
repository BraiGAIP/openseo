import { redirect } from "@/i18n/navigation";
import { getMemberships } from "@/lib/data";

export default async function AppIndex({ params }: PageProps<"/[locale]/app">) {
  const { locale } = await params;
  const [first] = await getMemberships();
  // Every user gets a personal workspace on sign-up, so this is only empty
  // if the bootstrap trigger failed.
  if (!first) throw new Error("No workspace found for this account.");
  redirect({ href: `/app/${first.slug}`, locale });
}
