// ---------------------------------------------------------------------------
// TII Zone system — 4 climate zones × 3 tension states = 12 feels-like labels
// ---------------------------------------------------------------------------

export type TiiZone = "quiet" | "active" | "hot" | "extreme"

export const ZONE_COLORS: Record<TiiZone, string> = {
  quiet:   "#4A90D9", // Blue — calm, cool
  active:  "#5DCAA5", // Teal/Green — growing energy
  hot:     "#E8651A", // Orange — heat
  extreme: "#E24B4A", // Red — maximum
}

export function tiiZone(tii: number): TiiZone {
  if (tii < 25) return "quiet"
  if (tii < 55) return "active"
  if (tii < 80) return "hot"
  return "extreme"
}

export function zoneColor(tii: number): string {
  return ZONE_COLORS[tiiZone(tii)]
}

// Feels-like label → emoji
export const FEELS_EMOJI: Record<string, string> = {
  Calm: "\u2601\uFE0F",
  "Subtle pressure": "\u{1F32B}\uFE0F",
  Grinding: "\u26CF",
  Flowing: "\u2600\uFE0F",
  Dynamic: "\u26A1",
  Pressured: "\u{1FAA8}",
  Expansive: "\u{1F305}",
  Charged: "\u26C8\uFE0F",
  Intense: "\u{1F525}",
  Powerful: "\u{1F680}",
  Volatile: "\u2694\uFE0F",
  Explosive: "\u{1F4A5}",
}

// Feels-like label → short mood description
export const FEELS_MOOD: Record<string, string> = {
  Calm: "Calm energy, perfect time for reflection",
  "Subtle pressure": "Light haze of tension in the air",
  Grinding: "Heavy but few events, endurance needed",
  Flowing: "Harmonious energy flow, things align",
  Dynamic: "Active energy, time for bold moves",
  Pressured: "External pressure demands adaptation",
  Expansive: "Grand scale energy, wide open",
  Charged: "Charged up, ready to discharge",
  Intense: "Hot energy, strong aspects firing",
  Powerful: "Powerful launch, breakthrough energy",
  Volatile: "Unpredictable, explosive potential",
  Explosive: "Maximum intensity, everything at once",
}
