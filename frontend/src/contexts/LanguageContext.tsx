import { createContext, useContext, useState, useCallback, type ReactNode } from "react"
import { en } from "../i18n/en"
import { ru } from "../i18n/ru"

export type Lang = "en" | "ru"

const translations: Record<Lang, Record<string, string>> = { en, ru }

interface LanguageContextValue {
  lang: Lang
  setLang: (lang: Lang) => void
  t: (key: string) => string
}

const LanguageContext = createContext<LanguageContextValue | null>(null)

function detectBrowserLang(): Lang {
  try {
    const nav = navigator.language || ""
    if (nav.startsWith("ru")) return "ru"
  } catch { /* SSR safe */ }
  return "en"
}

export function LanguageProvider({ children }: { children: ReactNode }) {
  const [lang, setLangState] = useState<Lang>(() => {
    const saved = localStorage.getItem("lang")
    if (saved === "en" || saved === "ru") return saved
    return detectBrowserLang()
  })

  const setLang = useCallback((l: Lang) => {
    setLangState(l)
    localStorage.setItem("lang", l)
  }, [])

  const t = useCallback((key: string): string => {
    return translations[lang][key] ?? translations.en[key] ?? key
  }, [lang])

  return (
    <LanguageContext.Provider value={{ lang, setLang, t }}>
      {children}
    </LanguageContext.Provider>
  )
}

export function useLanguage(): LanguageContextValue {
  const ctx = useContext(LanguageContext)
  if (!ctx) throw new Error("useLanguage must be used within LanguageProvider")
  return ctx
}
