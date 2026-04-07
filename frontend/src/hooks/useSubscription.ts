import { useState, useEffect, useCallback } from "react"
import { getAuthHeaders } from "../api"

interface SubscriptionStatus {
  plan: "free" | "pro_monthly" | "pro_annual" | "lifetime"
  is_pro: boolean
  expires_at: string | null
}

export function useSubscription() {
  const [isPro, setIsPro] = useState(false)
  const [plan, setPlan] = useState<string>("free")
  const [expiresAt, setExpiresAt] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  const refresh = useCallback(async () => {
    try {
      const headers = await getAuthHeaders()
      if (!headers.Authorization) {
        setIsPro(false)
        setPlan("free")
        setLoading(false)
        return
      }
      const res = await fetch("/api/v1/subscriptions/status", { headers })
      if (res.ok) {
        const data: SubscriptionStatus = await res.json()
        setIsPro(data.is_pro)
        setPlan(data.plan)
        setExpiresAt(data.expires_at)
      }
    } catch (err) {
      console.error("[useSubscription] error:", err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    refresh()
  }, [refresh])

  // Check URL params for payment success — poll until Pro or give up
  useEffect(() => {
    const params = new URLSearchParams(window.location.search)
    if (params.get("payment") !== "success") return
    // Clean URL immediately
    window.history.replaceState({}, "", window.location.pathname)

    let cancelled = false
    const delays = [2000, 4000, 6000, 10000, 15000] // retry schedule

    // Poll backend until subscription is active or retries exhausted
    const run = async () => {
      for (let i = 0; i < delays.length; i++) {
        if (cancelled) return
        await new Promise((r) => setTimeout(r, delays[i]))
        if (cancelled) return
        try {
          const headers = await getAuthHeaders()
          if (!headers.Authorization) continue
          const res = await fetch("/api/v1/subscriptions/status", { headers })
          if (res.ok) {
            const data: SubscriptionStatus = await res.json()
            if (data.is_pro) {
              setIsPro(true)
              setPlan(data.plan)
              setExpiresAt(data.expires_at)
              return // done — subscription activated
            }
          }
        } catch { /* retry */ }
      }
    }
    run()
    return () => { cancelled = true }
  }, [refresh])

  return { isPro, plan, expiresAt, loading, refresh }
}
