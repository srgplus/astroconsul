"""Email service: profile invites, and reports filed against a profile, via Resend."""

from __future__ import annotations

import html
import logging
from typing import Any

import httpx

from app.core.config import get_settings

logger = logging.getLogger(__name__)

RESEND_API_URL = "https://api.resend.com/emails"
FROM_EMAIL = "big3.me <onboarding@resend.dev>"


def send_invite_email(
    to_email: str,
    profile_name: str,
    inviter_email: str,
    invite_url: str,
) -> bool:
    """Send a profile transfer invite email. Returns True if sent successfully."""
    settings = get_settings()
    api_key = settings.resend_api_key

    if not api_key:
        logger.info(
            "RESEND_API_KEY not set — skipping email to %s (invite URL: %s)",
            to_email,
            invite_url,
        )
        return False

    html_body = f"""
<div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 16px;">
  <h2 style="color: #1a1a1a; margin-bottom: 8px;">You've been gifted a natal profile!</h2>
  <p style="color: #555; font-size: 16px; line-height: 1.5;">
    <strong>{inviter_email}</strong> created the natal profile
    <strong>"{profile_name}"</strong> for you on <strong>big3.me</strong>.
  </p>
  <p style="color: #555; font-size: 16px; line-height: 1.5;">
    Accept it to see your natal chart, daily cosmic weather, and transit forecasts.
  </p>
  <a href="{invite_url}"
     style="display: inline-block; background: #1a1a1a; color: #fff; padding: 14px 28px;
            border-radius: 10px; text-decoration: none; font-size: 16px; font-weight: 600;
            margin: 24px 0;">
    Accept Profile →
  </a>
  <p style="color: #999; font-size: 13px; margin-top: 32px;">
    This link expires in 7 days. If you didn't expect this email, you can safely ignore it.
  </p>
</div>
"""

    try:
        resp = httpx.post(
            RESEND_API_URL,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json={
                "from": FROM_EMAIL,
                "to": [to_email],
                "subject": f"{profile_name} — your natal profile on big3.me",
                "html": html_body,
            },
            timeout=10,
        )
        if resp.status_code in (200, 201):
            logger.info("Invite email sent to %s", to_email)
            return True
        logger.error("Resend API error %s: %s", resp.status_code, resp.text)
        return False
    except Exception as exc:
        logger.error("Failed to send invite email to %s: %s", to_email, exc)
        return False


def send_report_email(report: dict[str, Any], profile: dict[str, Any], reporter_email: str) -> bool:
    """Tells a person that a profile was reported, so it is acted on within a
    day rather than whenever someone next reads the table.

    The report is already stored before this runs; a mail that does not go out
    loses nothing but the nudge, so it is logged rather than raised."""
    settings = get_settings()
    api_key = settings.resend_api_key
    reason = str(report.get("reason", ""))

    if not api_key:
        logger.info(
            "RESEND_API_KEY not set — report %s on profile %s (%s) stored without a notification",
            report.get("report_id"),
            profile.get("profile_id"),
            reason,
        )
        return False

    rows = {
        "Report": f"#{report.get('report_id')}",
        "Reason": reason,
        "Details": report.get("details") or "",
        "Profile": f"{profile.get('profile_name', '')} (@{profile.get('username', '')})",
        "Profile id": profile.get("profile_id", ""),
        "Owner account": profile.get("user_id", ""),
        "Reported by": reporter_email,
        "Filed at": report.get("created_at", ""),
    }
    table = "".join(
        f"<tr><td style='padding:4px 12px 4px 0;color:#777'>{html.escape(label)}</td>"
        f"<td style='padding:4px 0'>{html.escape(str(value))}</td></tr>"
        for label, value in rows.items()
    )
    html_body = f"""
<div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 560px; padding: 24px 16px;">
  <h2 style="margin: 0 0 12px;">A profile was reported on big3.me</h2>
  <p style="color: #555;">Review it within 24 hours: remove the profile or the account if it breaks the
  Terms, and reply to the reporter.</p>
  <table style="font-size: 14px; border-collapse: collapse;">{table}</table>
</div>
"""

    try:
        resp = httpx.post(
            RESEND_API_URL,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json={
                "from": FROM_EMAIL,
                "to": [settings.moderation_email],
                "subject": f"Report #{report.get('report_id')}: {reason} on @{profile.get('username', '')}",
                "html": html_body,
            },
            timeout=10,
        )
        if resp.status_code in (200, 201):
            logger.info("Report email sent for report %s", report.get("report_id"))
            return True
        logger.error("Resend API error %s on report email: %s", resp.status_code, resp.text)
        return False
    except Exception as exc:
        logger.error("Failed to send report email for report %s: %s", report.get("report_id"), exc)
        return False
