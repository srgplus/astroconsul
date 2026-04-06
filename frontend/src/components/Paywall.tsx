import { useState } from "react"
import { createCheckoutSession } from "../api"

interface PaywallProps {
  /** Translation function */
  t: (key: string) => string
  /** Current language */
  lang: string
  /** Optional: what feature is gated */
  feature?: string
}

export function Paywall({ t, lang, feature }: PaywallProps) {
  const [loading, setLoading] = useState<string | null>(null)

  const handleCheckout = async (plan: string) => {
    setLoading(plan)
    try {
      const { checkout_url } = await createCheckoutSession(plan)
      window.location.href = checkout_url
    } catch (err) {
      console.error("[Paywall] checkout error:", err)
      setLoading(null)
    }
  }

  const isRu = lang === "ru"

  return (
    <div className="paywall-overlay">
      <div className="paywall-card">
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

        <div className="paywall-prices">
          <button
            type="button"
            className="paywall-btn paywall-btn--primary"
            onClick={() => handleCheckout("pro_monthly")}
            disabled={loading !== null}
          >
            {loading === "pro_monthly" ? (
              <span className="paywall-spinner" />
            ) : (
              <>
                <span className="paywall-btn-price">$7.99<small>/mo</small></span>
                <span className="paywall-btn-label">{isRu ? "Ежемесячно" : "Monthly"}</span>
              </>
            )}
          </button>

          <button
            type="button"
            className="paywall-btn paywall-btn--accent"
            onClick={() => handleCheckout("pro_annual")}
            disabled={loading !== null}
          >
            {loading === "pro_annual" ? (
              <span className="paywall-spinner" />
            ) : (
              <>
                <span className="paywall-btn-price">$59.99<small>/yr</small></span>
                <span className="paywall-btn-label">
                  {isRu ? "Годовой (экономия 37%)" : "Annual (save 37%)"}
                </span>
                <span className="paywall-badge">{isRu ? "Лучшая цена" : "Best value"}</span>
              </>
            )}
          </button>
        </div>

        <p className="paywall-compare">
          {isRu
            ? "$7.99/мес vs $5.00/мес при годовой подписке"
            : "$7.99/mo vs $5.00/mo with annual plan"
          }
        </p>
      </div>
    </div>
  )
}
