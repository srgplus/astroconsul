import {
  createContext,
  useContext,
  useEffect,
  useState,
  useCallback,
  type ReactNode,
} from "react";
import type { Session, User } from "@supabase/supabase-js";
import { Capacitor } from "@capacitor/core";
import { App } from "@capacitor/app";
import { Browser } from "@capacitor/browser";
import type { PluginListenerHandle } from "@capacitor/core";
import { supabase } from "../lib/supabase";

// Custom URL scheme registered natively (iOS Info.plist / Android intent-filter).
const AUTH_REDIRECT = "big3me://auth-callback";

// Reliable native detection. Capacitor injects this global into the WebView even
// when loading a remote server.url, so it works on both iOS and Android.
const isNative = (): boolean => Capacitor.isNativePlatform();

// Opens a provider OAuth flow. On native we use the system browser (Custom Tab /
// SFSafariViewController) — Google blocks OAuth inside embedded WebViews — and
// return to the app via the big3me:// deep link, which onAppUrlOpen completes.
async function startOAuth(provider: "google" | "apple"): Promise<void> {
  if (isNative()) {
    const { data, error } = await supabase.auth.signInWithOAuth({
      provider,
      options: { redirectTo: AUTH_REDIRECT, skipBrowserRedirect: true },
    });
    if (error) {
      console.error(`[Auth] ${provider} OAuth init error:`, error.message);
      return;
    }
    if (data?.url) await Browser.open({ url: data.url });
    return;
  }
  // Web: standard redirect flow handled by detectSessionInUrl on return.
  const { error } = await supabase.auth.signInWithOAuth({
    provider,
    options: { redirectTo: window.location.origin },
  });
  if (error) console.error(`[Auth] ${provider} OAuth error:`, error.message);
}

interface AuthContextValue {
  user: User | null;
  session: Session | null;
  loading: boolean;
  signIn: (email: string, password: string) => Promise<string | null>;
  signUp: (email: string, password: string) => Promise<string | null>;
  signInWithGoogle: () => Promise<void>;
  signInWithApple: () => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Listen for all auth changes — this handles:
    // - PKCE code exchange after OAuth redirect
    // - Session restore from localStorage
    // - Sign in / sign out
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, s) => {
      console.log("[Auth] event:", event, "session:", !!s);
      setSession(s);
      setLoading(false);
    });

    // Listen for native Apple Sign In fallback (iOS WKWebView postMessage)
    const handleAppleSignIn = async (e: MessageEvent) => {
      if (e.data?.type === "APPLE_SIGN_IN" && e.data.idToken) {
        console.log("[Auth] Native Apple Sign In token received");
        const { error } = await supabase.auth.signInWithIdToken({
          provider: "apple",
          token: e.data.idToken,
        });
        if (error) console.error("[Auth] Apple signInWithIdToken error:", error.message);
      }
    };
    window.addEventListener("message", handleAppleSignIn);

    // Native OAuth return: the system browser redirects to big3me://auth-callback?code=...
    // The OS reopens the app and fires appUrlOpen. Exchange the PKCE code for a session.
    let appUrlListener: PluginListenerHandle | undefined;
    if (isNative()) {
      App.addListener("appUrlOpen", async ({ url }) => {
        if (!url.includes("auth-callback")) return;
        console.log("[Auth] appUrlOpen received");
        try {
          const code = new URL(url).searchParams.get("code");
          if (!code) {
            console.error("[Auth] appUrlOpen missing code param:", url);
            return;
          }
          const { error } = await supabase.auth.exchangeCodeForSession(code);
          if (error) console.error("[Auth] exchangeCodeForSession error:", error.message);
        } catch (err) {
          console.error("[Auth] appUrlOpen handling failed:", err);
        } finally {
          // Close the in-app browser tab so the user lands back in the app.
          try {
            await Browser.close();
          } catch {
            /* no-op: tab may already be closed */
          }
        }
      }).then((handle) => {
        appUrlListener = handle;
      });
    }

    return () => {
      subscription.unsubscribe();
      window.removeEventListener("message", handleAppleSignIn);
      appUrlListener?.remove();
    };
  }, []);

  const signIn = useCallback(async (email: string, password: string): Promise<string | null> => {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    return error ? error.message : null;
  }, []);

  const signUp = useCallback(async (email: string, password: string): Promise<string | null> => {
    const { error } = await supabase.auth.signUp({ email, password });
    return error ? error.message : null;
  }, []);

  const signInWithGoogle = useCallback(() => startOAuth("google"), []);

  const signInWithApple = useCallback(() => startOAuth("apple"), []);

  const signOut = useCallback(async () => {
    await supabase.auth.signOut();
    setSession(null);
  }, []);

  const user = session?.user ?? null;

  return (
    <AuthContext.Provider
      value={{ user, session, loading, signIn, signUp, signInWithGoogle, signInWithApple, signOut }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used inside <AuthProvider>");
  return ctx;
}
