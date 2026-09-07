/**
 * Where the paid tier has to be invisible.
 *
 * The iOS app ships with no in-app purchase, so nothing reachable from inside
 * it may show, unlock or advertise Pro. Apple rejected the previous submission
 * under guideline 3.1.1 for exactly that: the app granted content bought on
 * the web without offering the same thing as an in-app purchase. The iOS build
 * therefore serves the free tier to every account, including one that pays on
 * big3.me, and hides every lock, price and upsell.
 *
 * A lock counts as an upsell. A row drawn greyed out with a padlock reads as a
 * paywall to a reviewer even when nothing is for sale, so the gated content is
 * left out rather than locked.
 */
export const hidesPaidTier = (): boolean =>
  typeof window !== "undefined" &&
  !!(window as { Capacitor?: { isNativePlatform?: () => boolean } }).Capacitor?.isNativePlatform?.()
