import { useState, useEffect, useCallback } from "react"

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
      const { getAuthHeaders } = await import("../api")
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

  // Check URL params for payment success
  useEffect(() => {
    const params = new URLSearchParams(window.location.search)
    if (params.get("payment") === "success") {
      // Refresh subscription status after successful payment
      setTimeout(refresh, 2000)
      // Clean URL
      window.history.replaceState({}, "", window.location.pathname)
    }
  }, [refresh])

  return { isPro, plan, expiresAt, loading, refresh }
}
