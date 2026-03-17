import type React from "react"

/**
 * Mobile browsers swallow onClick inside overflow-y:auto scroll containers.
 * This helper returns onTouchStart + onTouchEnd + onClick handlers that work:
 * - onTouchEnd fires immediately on mobile (bypasses scroll container click delay)
 * - onClick fires on desktop (mouse)
 * - Tracks finger movement to distinguish tap from scroll (< 10px threshold)
 */
export function useMobileTap() {
  const startY = { current: 0 }
  const handled = { current: false }

  return (cb: () => void) => ({
    onTouchStart: (e: React.TouchEvent) => {
      startY.current = e.touches[0].clientY
      handled.current = false
    },
    onTouchEnd: (e: React.TouchEvent) => {
      const dy = Math.abs(e.changedTouches[0].clientY - startY.current)
      if (dy < 10) {
        e.preventDefault() // prevent ghost click
        handled.current = true
        cb()
      }
    },
    onClick: () => {
      if (!handled.current) cb()
      handled.current = false
    },
  })
}
