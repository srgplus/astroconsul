// Time-of-day modifiers for feels_like descriptions
// Time windows: morning (6-12), afternoon (12-18), evening (18-23), night (23-6)

import modifiersData from "./data/feels_like_time_modifiers.json"

export type TimeWindow = "morning" | "afternoon" | "evening" | "night"

export function getTimeWindow(hour: number): TimeWindow {
  if (hour >= 6 && hour < 12) return "morning"
  if (hour >= 12 && hour < 18) return "afternoon"
  if (hour >= 18 && hour < 23) return "evening"
  return "night"
}

export function getTimeWindowFromUTC(utcDatetime: string, timezone?: string): TimeWindow {
  try {
    const d = new Date(utcDatetime.endsWith("Z") ? utcDatetime : utcDatetime + "Z")
    const hour = parseInt(
      new Intl.DateTimeFormat("en-US", {
        timeZone: timezone || undefined,
        hour: "numeric",
        hour12: false,
      }).format(d),
      10
    )
    return getTimeWindow(hour)
  } catch {
    return "afternoon" // fallback
  }
}

type ModifierEntry = { headline: string; description: string }

type ModifiersJSON = Record<string, Record<string, Record<string, ModifierEntry>>>

const modifiers: ModifiersJSON = modifiersData

export function getFeelsModifier(
  feelsLike: string,
  timeWindow: TimeWindow,
  lang: "en" | "ru"
): ModifierEntry | null {
  return modifiers[feelsLike]?.[timeWindow]?.[lang] ?? null
}

const TIME_WINDOW_LABELS: Record<TimeWindow, Record<string, string>> = {
  morning:   { en: "Morning",   ru: "Утро" },
  afternoon: { en: "Afternoon", ru: "День" },
  evening:   { en: "Evening",   ru: "Вечер" },
  night:     { en: "Night",     ru: "Ночь" },
}

export function getTimeWindowLabel(tw: TimeWindow, lang: "en" | "ru"): string {
  return TIME_WINDOW_LABELS[tw]?.[lang] ?? tw
}

const TIME_WINDOW_RANGES: Record<TimeWindow, string> = {
  morning:   "6:00–12:00",
  afternoon: "12:00–18:00",
  evening:   "18:00–23:00",
  night:     "23:00–6:00",
}

export function getTimeWindowRange(tw: TimeWindow): string {
  return TIME_WINDOW_RANGES[tw]
}
