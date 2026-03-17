import { useState, useRef, useCallback, useEffect } from "react"
import type { ProfileSummary } from "../types"
import { zoneColor, FEELS_EMOJI } from "../tii-zones"
import { useLanguage } from "../contexts/LanguageContext"

export type ProfileTiiData = {
  tii: number
  tension_ratio: number
  feels_like: string
  location: string
}

type ProfileListProps = {
  profiles: ProfileSummary[]
  activeProfileId: string | null
  onSelect: (id: string) => void
  tiiMap: Record<string, ProfileTiiData>
  primaryProfileId: string | null
  onReorder: (orderedIds: string[]) => void
  onUnfollow?: (id: string) => void
}

export function ProfileList({
  profiles,
  activeProfileId,
  onSelect,
  tiiMap,
  primaryProfileId,
  onReorder,
  onUnfollow,
}: ProfileListProps) {
  const { t } = useLanguage()
  const [dragId, setDragId] = useState<string | null>(null)
  const [overId, setOverId] = useState<string | null>(null)
  const [ctxMenu, setCtxMenu] = useState<{ id: string; x: number; y: number } | null>(null)
  const dragIdxRef = useRef<number>(-1)

  const handleDragStart = useCallback((e: React.DragEvent, id: string, idx: number) => {
    setDragId(id)
    dragIdxRef.current = idx
    e.dataTransfer.effectAllowed = "move"
    if (e.currentTarget instanceof HTMLElement) {
      e.dataTransfer.setDragImage(e.currentTarget, 0, 0)
    }
  }, [])

  const handleDragOver = useCallback((e: React.DragEvent, id: string) => {
    e.preventDefault()
    e.dataTransfer.dropEffect = "move"
    if (id !== dragId && id !== primaryProfileId) {
      setOverId(id)
    }
  }, [dragId, primaryProfileId])

  const handleDrop = useCallback((e: React.DragEvent, dropId: string, dropIdx: number) => {
    e.preventDefault()
    if (!dragId || dragId === dropId) {
      setDragId(null)
      setOverId(null)
      return
    }

    const ids = profiles.map((p) => p.profile_id)
    const fromIdx = ids.indexOf(dragId)
    if (fromIdx === -1) return

    ids.splice(fromIdx, 1)
    const toIdx = fromIdx < dropIdx ? dropIdx - 1 : dropIdx
    ids.splice(toIdx, 0, dragId)

    onReorder(ids)
    setDragId(null)
    setOverId(null)
  }, [dragId, profiles, onReorder])

  const handleDragEnd = useCallback(() => {
    setDragId(null)
    setOverId(null)
  }, [])

  const handleContextMenu = useCallback((e: React.MouseEvent, id: string) => {
    e.preventDefault()
    setCtxMenu({ id, x: e.clientX, y: e.clientY })
  }, [])

  const ctxRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!ctxMenu) return
    const handler = (e: MouseEvent) => {
      if (ctxRef.current && ctxRef.current.contains(e.target as Node)) return
      setCtxMenu(null)
    }
    window.addEventListener("mousedown", handler)
    return () => window.removeEventListener("mousedown", handler)
  }, [ctxMenu])

  if (!profiles.length) {
    return (
      <div className="empty-card">
        <strong>{t("profileList.empty")}</strong>
        <span>{t("profileList.emptyDesc")}</span>
      </div>
    )
  }

  return (
    <div className="profile-list">
      {profiles.map((p, idx) => {
        const tii = tiiMap[p.profile_id]
        const accent = tii ? zoneColor(tii.tii) : undefined
        const emoji = tii ? (FEELS_EMOJI[tii.feels_like] ?? "\u2728") : undefined
        const feelsLabel = tii ? t(`feels.${tii.feels_like}`) : undefined
        const rawLoc = tii?.location ?? ""
        const tzLabel = (() => {
          // If it's a city name (contains comma), use first part
          if (rawLoc.includes(",")) return rawLoc.split(",")[0].trim()
          // If it's a timezone ID like "America/Los_Angeles", extract city + offset
          if (rawLoc.includes("/")) {
            const city = rawLoc.split("/").pop()?.replace(/_/g, " ") ?? rawLoc
            try {
              const offsetStr = new Intl.DateTimeFormat("en", { timeZone: rawLoc, timeZoneName: "shortOffset" })
                .formatToParts(new Date())
                .find((pt) => pt.type === "timeZoneName")?.value ?? ""
              return `${city} ${offsetStr}`
            } catch {
              return city
            }
          }
          return rawLoc.replace(/_/g, " ")
        })()

        const isPrimary = p.profile_id === primaryProfileId
        const isFollowed = p.is_following === true && p.is_own === false
        const isDragging = p.profile_id === dragId
        const isDragOver = p.profile_id === overId

        return (
          <div
            key={p.profile_id}
            className={`pli-drag-wrap${isDragOver ? " pli-drag-over" : ""}${isDragging ? " pli-dragging" : ""}`}
            draggable={!isPrimary}
            onDragStart={(e) => handleDragStart(e, p.profile_id, idx)}
            onDragOver={(e) => handleDragOver(e, p.profile_id)}
            onDrop={(e) => handleDrop(e, p.profile_id, idx)}
            onDragEnd={handleDragEnd}
            onContextMenu={isFollowed ? (e) => handleContextMenu(e, p.profile_id) : undefined}
          >
            <button
              type="button"
              className={`profile-list-item ${p.profile_id === activeProfileId ? "active" : ""} ${tii ? "has-tii" : ""}`}
              onClick={() => onSelect(p.profile_id)}
            >
              {tii ? (
                <>
                  <div className="pli-name-row">
                    <div className="pli-name">{p.profile_name}</div>
                    <div className="pli-tii" style={{ color: accent }}>{Math.round(tii.tii)}&deg;</div>
                  </div>
                  <div className="pli-username">@{p.username}</div>
                  <div className="pli-location">{tzLabel}</div>
                  <div className="pli-bottom">
                    <span className="pli-feels" style={{ color: accent }}>{feelsLabel}</span>
                    <span className="pli-tension">T {Math.round(tii.tension_ratio * 100)}%</span>
                  </div>
                </>
              ) : (
                <>
                  <strong>{p.profile_name}</strong>
                  <div className="pli-username">@{p.username}</div>
                </>
              )}
            </button>
          </div>
        )
      })}

      {ctxMenu && onUnfollow && (
        <div
          ref={ctxRef}
          className="pli-ctx-menu"
          style={{ top: ctxMenu.y, left: ctxMenu.x }}
        >
          <button
            type="button"
            className="pli-ctx-item"
            onClick={() => {
              onUnfollow(ctxMenu.id)
              setCtxMenu(null)
            }}
          >
            {t("sidebar.unfollow")}
          </button>
        </div>
      )}
    </div>
  )
}
