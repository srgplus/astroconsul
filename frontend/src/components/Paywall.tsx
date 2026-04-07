import { useState } from "react"
import { createCheckoutSession } from "../api"

const isNativeApp = (): boolean =>
  typeof window !== "undefined" && !!(window as any).Capacitor?.isNativePlatform?.()

const CONTACT_EMAIL = "big3meapp@gmail.com"

interface PaywallProps {
  /** Translation function */
  t: (key: string) => string
  /** Current language */
  lang: string
  /** Optional: what feature is gated */
  feature?: string
  /** Optional: close handler for modal usage */
  onClose?: () => void
}

export function Paywall({ t, lang, feature, onClose }: PaywallProps) {
  const [loading, setLoading] = useState<string | null>(null)
  const [selectedPlan, setSelectedPlan] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const native = isNativeApp()

  const handleCheckout = async () => {
    if (!selectedPlan) return
    setLoading(selectedPlan)
    setError(null)
    try {
      const { checkout_url } = await createCheckoutSession(selectedPlan)
      if (checkout_url) {
        window.location.href = checkout_url
      } else {
        setError("Could not create checkout session. Please try again.")
        setLoading(null)
      }
    } catch (err) {
      console.error("[Paywall] checkout error:", err)
      setError(err instanceof Error ? err.message : "Payment system error. Please try again later.")
      setLoading(null)
    }
  }

  const handleContactEmail = () => {
    const subject = encodeURIComponent("big3.me Pro — Subscription Request")
    const body = encodeURIComponent("Hi! I'd like to upgrade to big3.me Pro.\n\nPlease send me the details.")
    window.location.href = `mailto:${CONTACT_EMAIL}?subject=${subject}&body=${body}`
  }

  const isRu = lang === "ru"

  return (
    <div className="paywall-overlay">
      <div className="paywall-card">
        {onClose ? (
          <button type="button" className="paywall-close" onClick={onClose}>&times;</button>
        ) : null}
        <div className="paywall-icon">
          <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
            <path d="M7 11V7a5 5 0 0 1 10 0v4" />
          </svg>
        </div>

        <h3 className="paywall-title">
          {isRu ? "Разблокируйте big3.me Pro" : "Unlock big3.me Pro"}
        </h3>

        {feature && (
          <p className="paywall-feature">
            {isRu ? `${feature} — доступно в Pro` : `${feature} — available with Pro`}
          </p>
        )}

        <ul className="paywall-benefits">
          <li>{isRu ? "Полный 10-дневный прогноз" : "Full 10-day forecast"}</li>
          <li>{isRu ? "Детальные описания транзитов" : "Detailed transit descriptions"}</li>
          <li>{isRu ? "Космический климат" : "Cosmic climate analysis"}</li>
          <li>{isRu ? "Таймлайн аспектов" : "Aspect timeline"}</li>
        </ul>

        {native ? (
          <>
            <p className="paywall-contact-text">
              {isRu
                ? "Чтобы оформить подписку, свяжитесь с нами:"
                : "To subscribe, contact us:"}
            </p>

            <button
              type="button"
              className="paywall-purchase-btn"
              onClick={handleContactEmail}
            >
              {isRu ? "Связаться с нами" : "Contact Us"}
            </button>
          </>
        ) : (
          <>
            <div className="paywall-prices">
              <button
                type="button"
                className={`paywall-btn paywall-btn--primary${selectedPlan === "pro_monthly" ? " paywall-btn--selected" : ""}`}
                onClick={() => setSelectedPlan("pro_monthly")}
              >
                <span className="paywall-btn-price">$7.99<small>/mo</small></span>
                <span className="paywall-btn-label">{isRu ? "Ежемесячно" : "Monthly"}</span>
              </button>

              <button
                type="button"
                className={`paywall-btn paywall-btn--accent${selectedPlan === "pro_annual" ? " paywall-btn--selected" : ""}`}
                onClick={() => setSelectedPlan("pro_annual")}
              >
                <span className="paywall-btn-price">$59.99<small>/yr</small></span>
                <span className="paywall-btn-label">
                  {isRu ? "Ежегодно (экономия 37%)" : "Annual (save 37%)"}
                </span>
                <span className="paywall-badge">{isRu ? "Лучшая цена" : "Best value"}</span>
              </button>
            </div>

            <button
              type="button"
              className="paywall-purchase-btn"
              disabled={!selectedPlan || !!loading}
              onClick={handleCheckout}
            >
              {loading ? (
                <span className="paywall-spinner" />
              ) : (
                isRu ? "Оформить подписку" : "Purchase"
              )}
            </button>

            {error && <p style={{ color: "#ff453a", fontSize: "0.8rem", marginBottom: 8 }}>{error}</p>}
            <p className="paywall-compare">
              {isRu
                ? "$7.99/мес vs $5.00/мес при годовой подписке"
                : "$7.99/mo vs $5.00/mo with annual plan"
              }
            </p>
          </>
        )}
      </div>
    </div>
  )
}
