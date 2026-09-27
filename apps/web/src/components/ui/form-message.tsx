import { cn } from "@/lib/utils";

export function FormMessage({ message, tone = "error" }: { message?: string | null; tone?: "error" | "success" }) {
  if (!message) return null;
  return (
    <p
      role={tone === "error" ? "alert" : "status"}
      className={cn("text-sm", tone === "error" ? "text-danger-text" : "text-success-text")}
    >
      {message}
    </p>
  );
}
