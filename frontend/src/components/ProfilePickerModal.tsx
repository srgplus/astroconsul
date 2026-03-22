import { useState, useRef, useCallback, useEffect } from "react"
import { searchPublicProfiles } from "../api"
import type { PublicSearchResult, ProfileSummary } from "../types"

const SIGN_GLYPHS: Record<string, string> = {
  Aries: "\u2648", Taurus: "\u2649", Gemini: "\u264A", Cancer: "\u264B",
  Leo: "\u264C", Virgo: "\u264D", Libra: "\u264E", Scorpio: "\u264F",
  Sagittarius: "\u2650", Capricorn: "\u2651", Aquarius: "\u2652", Pisces: "\u2653",
}

type Props = {
  open: boolean
  onClose: () => void
  onSelect: (profileId: string, name: string, handle: string, natalSummary: Record<string, string> | string | null) => void
  /** Already-followed profiles for quick pick */
  profiles: ProfileSummary[]
  /** Current user's active profile id — excluded from results */
  excludeProfileId?: string | null
}

export default function ProfilePickerModal({ open, onClose, onSelect, profiles, excludeProfileId }: Props) {
  const [query, setQuery] = useState("")
  const [results, setResults] = useState<PublicSearchResult[]>([])
  const [searching, setSearching] = useState(false)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const abortRef = useRef<AbortController | null>(null)

  const doSearch = useCallback((q: string) => {
    abortRef.current?.abort()
    if (q.trim().length < 2) {
      setResults([])
      setSearching(false)
      return
    }
    setSearching(true)
    const ctrl = new AbortController()
    abortRef.current = ctrl
    searchPublicProfiles(q.trim(), ctrl.signal)
      .then((res) => {
        setResults(res.filter((r) => r.profile_id !== excludeProfileId))
        setSearching(false)
      })
      .catch((err) => {
        if (err.name !== "AbortError") {
          console.error("Profile search failed:", err)
          setSearching(false)
        }
      })
  }, [excludeProfileId])

  const handleInput = (value: string) => {
    setQuery(value)
    if (debounceRef.current) clearTimeout(debounceRef.current)
    debounceRef.current = setTimeout(() => doSearch(value), 300)
  }

  // Clean up on close
  useEffect(() => {
    if (!open) {
      setQuery("")
      setResults([])
    }
  }, [open])

  if (!open) return null

  // Filter local profiles by query for quick picks
  const q = query.toLowerCase()
  const localFiltered = profiles.filter((p) =>
    p.profile_id !== excludeProfileId && (
      !q || p.profile_name.toLowerCase().includes(q) || p.username.toLowerCase().includes(q)
    )
  )

  const renderNatalSummary = (ns: Record<string, string> | string | null) => {
    if (!ns || typeof ns === "string") return null
    const sun = ns.Sun || ns.sun
    const moon = ns.Moon || ns.moon
    const asc = ns.Ascendant || ns.ascendant || ns.ASC
    return (
      <span className="picker-big3">
        {sun ? <span className="picker-sign-badge">{SIGN_GLYPHS[sun] || ""}</span> : null}
        {moon ? <span className="picker-sign-badge">{SIGN_GLYPHS[moon] || ""}</span> : null}
        {asc ? <span className="picker-sign-badge">{SIGN_GLYPHS[asc] || ""}</span> : null}
      </span>
    )
  }

  return (
    <div className="picker-overlay" onClick={(e) => { if (e.target === e.currentTarget) onClose() }}>
      <div className="picker-modal">
        <div className="picker-header">
          <h3>Select Profile</h3>
          <button type="button" className="settings-close" onClick={onClose}>&times;</button>
        </div>
        <div className="picker-search">
          <input
            type="text"
            placeholder="Search by name or @handle..."
            value={query}
            onChange={(e) => handleInput(e.target.value)}
            autoFocus
          />
        </div>
        <div className="picker-list">
          {searching && <div className="picker-loading"><span className="spinner" /></div>}

          {/* Local (followed) profiles */}
          {localFiltered.length > 0 && !searching && (
            <>
              {localFiltered.map((p) => (
                <button
                  key={p.profile_id}
                  type="button"
                  className="picker-item"
                  onClick={() => onSelect(p.profile_id, p.profile_name, p.username, null)}
                >
                  <div className="picker-item-info">
                    <span className="picker-item-name">{p.profile_name}</span>
                    <span className="picker-item-handle">@{p.username}</span>
                  </div>
                </button>
              ))}
            </>
          )}

          {/* Public search results */}
          {results.length > 0 && !searching && (
            <>
              {query.trim().length >= 2 && localFiltered.length > 0 && (
                <div className="picker-divider">Public</div>
              )}
              {results.map((r) => (
                <button
                  key={r.profile_id}
                  type="button"
                  className="picker-item"
                  onClick={() => onSelect(r.profile_id, r.profile_name, r.username, r.natal_summary)}
                >
                  <div className="picker-item-info">
                    <span className="picker-item-name">{r.profile_name}</span>
                    <span className="picker-item-handle">@{r.username}</span>
                  </div>
                  {renderNatalSummary(r.natal_summary)}
                </button>
              ))}
            </>
          )}

          {!searching && query.trim().length >= 2 && results.length === 0 && localFiltered.length === 0 && (
            <div className="picker-empty">No profiles found</div>
          )}
        </div>
      </div>
    </div>
  )
}
