/** "October 2026" in the given language, from a calendar month. */
export const monthYear =
  (tag: string) =>
  ({ year, month }: { year: number; month: number }) =>
    new Intl.DateTimeFormat(tag, {
      year: "numeric",
      month: "long",
      timeZone: "UTC",
    }).format(new Date(Date.UTC(year, month - 1, 1)));
