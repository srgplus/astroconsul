import { useState, useEffect, useRef, useCallback } from "react"
import { createPortal } from "react-dom"
import { searchLocations, type PlaceCandidate } from "../api"

type Props = {
  value: string
  onChange: (value: string) => void
  onSelect: (place: PlaceCandidate) => void
  placeholder?: string
}

export function LocationAutocomplete({ value, onChange, onSelect, placeholder }: Props) {
  const [results, setResults] = useState<PlaceCandidate[]>([])
  const [open, setOpen] = useState(false)
  const [loading, setLoading] = useState(false)
  const [listStyle, setListStyle] = useState<React.CSSProperties>({})
  const abortRef = useRef<AbortController | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const listRef = useRef<HTMLUListElement>(null)
  const debounceRef = useRef<ReturnType<typeof setTimeout>>()
  const typingRef = useRef(false)

  // Position the dropdown relative to the input using fixed positioning
  const updatePosition = useCallback(() => {
    const el = inputRef.current
    if (!el) return
    const rect = el.getBoundingClientRect()
    setListStyle({
      position: "fixed",
      top: rect.bottom + 4,
      left: rect.left,
      width: rect.width,
      zIndex: 99999,
    })
  }, [])

  // Debounced search
  useEffect(() => {
    clearTimeout(debounceRef.current)
    if (!typingRef.current || value.trim().length < 2) {
      setResults([])
      setOpen(false)
      return
    }
    debounceRef.current = setTimeout(() => {
      abortRef.current?.abort()
      const ctrl = new AbortController()
      abortRef.current = ctrl
      setLoading(true)
      searchLocations(value.trim(), ctrl.signal)
        .then((r) => {
          if (!ctrl.signal.aborted) {
            setResults(r)
            if (r.length > 0) {
              updatePosition()
              setOpen(true)
            } else {
              setOpen(false)
            }
          }
        })
        .catch(() => {})
        .finally(() => {
          if (!ctrl.signal.aborted) setLoading(false)
        })
    }, 400)
    return () => {
      clearTimeout(debounceRef.current)
      abortRef.current?.abort()
    }
  }, [value, updatePosition])

  // Close on outside click/touch
  useEffect(() => {
    function handler(e: Event) {
      const target = e.target as Node
      if (
        inputRef.current && !inputRef.current.contains(target) &&
        listRef.current && !listRef.current.contains(target)
      ) {
        setOpen(false)
      }
    }
    document.addEventListener("mousedown", handler)
    document.addEventListener("touchstart", handler)
    return () => {
      document.removeEventListener("mousedown", handler)
      document.removeEventListener("touchstart", handler)
    }
  }, [])

  // Reposition on scroll instead of closing (mobile keyboard causes scroll)
  useEffect(() => {
    if (!open) return
    function onScroll() { updatePosition() }
    window.addEventListener("scroll", onScroll, true)
    return () => window.removeEventListener("scroll", onScroll, true)
  }, [open, updatePosition])

  // Reposition on resize (keyboard show/hide on mobile)
  useEffect(() => {
    if (!open) return
    const onResize = () => updatePosition()
    window.addEventListener("resize", onResize)
    if (window.visualViewport) {
      window.visualViewport.addEventListener("resize", onResize)
      window.visualViewport.addEventListener("scroll", onResize)
    }
    return () => {
      window.removeEventListener("resize", onResize)
      if (window.visualViewport) {
        window.visualViewport.removeEventListener("resize", onResize)
        window.visualViewport.removeEventListener("scroll", onResize)
      }
    }
  }, [open, updatePosition])

  function handleInput(e: React.ChangeEvent<HTMLInputElement>) {
    typingRef.current = true
    onChange(e.target.value)
  }

  function handleSelect(place: PlaceCandidate) {
    typingRef.current = false
    setOpen(false)
    setResults([])
    onSelect(place)
  }

  /** Shorten long Nominatim display names */
  function shortName(display: string): string {
    const parts = display.split(",").map((s) => s.trim())
    if (parts.length <= 3) return display
    return `${parts[0]}, ${parts[parts.length - 2]}, ${parts[parts.length - 1]}`
  }

  const dropdown = open && results.length > 0 ? createPortal(
    <ul className="loc-ac__list" ref={listRef} style={listStyle}>
      {results.map((r, i) => (
        <li
          key={`${r.latitude}-${r.longitude}-${i}`}
          onPointerDown={(e) => {
            e.preventDefault()
            handleSelect(r)
          }}
        >
          <span className="loc-ac__name">{shortName(r.display_name)}</span>
          {r.timezone ? <span className="loc-ac__tz">{r.timezone}</span> : null}
        </li>
      ))}
    </ul>,
    document.body,
  ) : null

  return (
    <div className="loc-ac">
      <input
        ref={inputRef}
        type="text"
        value={value}
        onChange={handleInput}
        placeholder={placeholder ?? "Search city..."}
        autoComplete="off"
      />
      {loading && <span className="loc-ac__spinner" />}
      {dropdown}
    </div>
  )
}
