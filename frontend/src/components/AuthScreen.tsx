import { useState } from "react";
import { useAuth } from "../contexts/AuthContext";
import { useLanguage } from "../contexts/LanguageContext";

export default function AuthScreen({ onBack }: { onBack?: () => void } = {}) {
  const { signIn, signUp, signInWithGoogle, signInWithApple } = useAuth();
  const { t } = useLanguage();
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [signUpSuccess, setSignUpSuccess] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      if (mode === "signin") {
        const err = await signIn(email, password);
        if (err) setError(err);
      } else {
        const err = await signUp(email, password);
        if (err) {
          setError(err);
        } else {
          setSignUpSuccess(true);
        }
      }
    } finally {
      setLoading(false);
    }
  };

  if (signUpSuccess) {
    return (
      <div className="auth-screen">
        <div className="auth-form">
          <h1 className="auth-logo">{t("auth.logo")}</h1>
          <div className="auth-success">
            <p>{t("auth.checkEmail")}</p>
            <button
              className="auth-btn"
              onClick={() => {
                setSignUpSuccess(false);
                setMode("signin");
              }}
            >
              {t("auth.backToSignIn")}
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="auth-screen">
      <div className="auth-form">
        {onBack ? (
          <button type="button" className="landing-back-btn" onClick={onBack} style={{ marginBottom: 8 }}>
            &larr; {t("landing.back")}
          </button>
        ) : null}
        <h1 className="auth-logo">{t("auth.logo")}</h1>
        <p className="auth-subtitle">
          {mode === "signin" ? t("auth.signInSubtitle") : t("auth.signUpSubtitle")}
        </p>

        <form onSubmit={handleSubmit}>
          <input
            className="auth-input"
            type="email"
            placeholder={t("auth.email")}
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            autoComplete="email"
          />
          <input
            className="auth-input"
            type="password"
            placeholder={t("auth.password")}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            minLength={6}
            autoComplete={mode === "signin" ? "current-password" : "new-password"}
          />
          {error ? <p className="auth-error">{error}</p> : null}
          <button className="auth-btn auth-btn--primary" type="submit" disabled={loading}>
            {loading ? "..." : mode === "signin" ? t("auth.signIn") : t("auth.signUp")}
          </button>
        </form>

        <div className="auth-divider">
          <span>{t("auth.or")}</span>
        </div>

        <button className="auth-btn auth-btn--social" onClick={signInWithGoogle} type="button">
          <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
            <path d="M17.64 9.2c0-.637-.057-1.251-.164-1.84H9v3.481h4.844a4.14 4.14 0 0 1-1.796 2.716v2.259h2.908c1.702-1.567 2.684-3.875 2.684-6.615Z" fill="#4285F4"/>
            <path d="M9 18c2.43 0 4.467-.806 5.956-2.18l-2.908-2.259c-.806.54-1.837.86-3.048.86-2.344 0-4.328-1.584-5.036-3.711H.957v2.332A8.997 8.997 0 0 0 9 18Z" fill="#34A853"/>
            <path d="M3.964 10.71A5.41 5.41 0 0 1 3.682 9c0-.593.102-1.17.282-1.71V4.958H.957A8.997 8.997 0 0 0 0 9c0 1.452.348 2.827.957 4.042l3.007-2.332Z" fill="#FBBC05"/>
            <path d="M9 3.58c1.321 0 2.508.454 3.44 1.345l2.582-2.58C13.463.891 11.426 0 9 0A8.997 8.997 0 0 0 .957 4.958L3.964 7.29C4.672 5.163 6.656 3.58 9 3.58Z" fill="#EA4335"/>
          </svg>
          {t("auth.continueGoogle")}
        </button>

        <button className="auth-btn auth-btn--social" onClick={signInWithApple} type="button">
          <svg width="18" height="18" viewBox="0 0 18 18" fill="currentColor">
            <path d="M14.94 9.88c-.02-2.15 1.76-3.18 1.84-3.23-1-1.46-2.56-1.66-3.12-1.69-1.33-.13-2.59.78-3.26.78-.67 0-1.71-.76-2.81-.74-1.45.02-2.78.84-3.53 2.14-1.5 2.61-.38 6.47 1.08 8.59.72 1.04 1.57 2.2 2.69 2.16 1.08-.04 1.49-.7 2.8-.7 1.3 0 1.68.7 2.82.68 1.16-.02 1.89-1.06 2.6-2.1.82-1.2 1.16-2.36 1.18-2.42-.03-.01-2.26-.87-2.29-3.47ZM12.83 3.63c.6-.72 1-1.73.89-2.73-.86.04-1.9.57-2.52 1.29-.55.64-1.03 1.66-.9 2.64.96.07 1.94-.49 2.53-1.2Z"/>
          </svg>
          {t("auth.continueApple")}
        </button>

        <p className="auth-toggle">
          {mode === "signin" ? (
            <>
              {t("auth.noAccount")}{" "}
              <button type="button" onClick={() => { setMode("signup"); setError(null); }}>
                {t("auth.signUp")}
              </button>
            </>
          ) : (
            <>
              {t("auth.hasAccount")}{" "}
              <button type="button" onClick={() => { setMode("signin"); setError(null); }}>
                {t("auth.signIn")}
              </button>
            </>
          )}
        </p>
      </div>
    </div>
  );
}
