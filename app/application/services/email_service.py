"""Email service: profile invites, and reports filed against a profile, via Resend."""

from __future__ import annotations

import html
import logging
from typing import Any

import httpx

from app.core.config import get_settings

logger = logging.getLogger(__name__)

RESEND_API_URL = "https://api.resend.com/emails"


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
                "from": settings.email_from,
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


def _multiline(text: str) -> str:
    return html.escape(text).replace("\n", "<br>")


def _conversation_html(conversation: dict[str, Any]) -> str:
    """The chat a report came from, oldest message first: when, who (and
    which side of the report), what. Everything escaped: it is user text."""
    messages = conversation.get("messages") or []
    if not messages:
        return "<p style='color:#777'>The chat has no messages.</p>"
    cell = "padding:4px 12px 4px 0;vertical-align:top"
    rows = "".join(
        "<tr>"
        f"<td style='{cell};color:#777;white-space:nowrap'>{html.escape(str(message.get('created_at', '')))}</td>"
        f"<td style='{cell}'><strong>{html.escape(str(message.get('sender_name', '')))}</strong><br>"
        f"<span style='color:#777'>{html.escape(str(message.get('role', '')))}</span></td>"
        f"<td style='padding:4px 0;vertical-align:top'>{_multiline(str(message.get('body', '')))}</td>"
        "</tr>"
        for message in messages
    )
    return (
        f"<h3 style='margin: 20px 0 8px;'>The conversation: last {len(messages)} messages of chat "
        f"#{html.escape(str(conversation.get('chat_id', '')))}, oldest first, times in UTC</h3>"
        f"<table style='font-size: 14px; border-collapse: collapse;'>{rows}</table>"
    )


def report_email(
    report: dict[str, Any],
    profile: dict[str, Any],
    reporter_email: str,
    conversation: dict[str, Any] | None = None,
) -> tuple[str, str]:
    """The subject and body of the mail a report sends to the moderation
    inbox, with the conversation when it was reported from a chat."""
    reason = str(report.get("reason", ""))
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
    if conversation is not None:
        rows["Chat"] = f"#{conversation.get('chat_id', '')} (messages below)"
    table = "".join(
        f"<tr><td style='padding:4px 12px 4px 0;color:#777'>{html.escape(label)}</td>"
        f"<td style='padding:4px 0'>{html.escape(str(value))}</td></tr>"
        for label, value in rows.items()
    )
    conversation_block = _conversation_html(conversation) if conversation is not None else ""
    html_body = f"""
<div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 560px; padding: 24px 16px;">
  <h2 style="margin: 0 0 12px;">A profile was reported on big3.me</h2>
  <p style="color: #555;">Review it within 24 hours: remove the profile or the account if it breaks the
  Terms, and reply to the reporter.</p>
  <table style="font-size: 14px; border-collapse: collapse;">{table}</table>
  {conversation_block}
</div>
"""
    subject = f"Report #{report.get('report_id')}: {reason} on @{profile.get('username', '')}"
    if conversation is not None:
        subject += " (from a chat)"
    return subject, html_body


def send_report_email(
    report: dict[str, Any],
    profile: dict[str, Any],
    reporter_email: str,
    *,
    conversation: dict[str, Any] | None = None,
) -> bool:
    """Tells a person that a profile was reported, so it is acted on within a
    day rather than whenever someone next reads the table. Reported from a
    chat, the mail carries the chat's latest messages (`conversation`), which
    is the only time anyone but the two of them reads a conversation.

    The report is already stored before this runs; a mail that does not go out
    loses nothing but the nudge, so it is logged rather than raised."""
    settings = get_settings()
    api_key = settings.resend_api_key

    if not api_key:
        logger.info(
            "RESEND_API_KEY not set: report %s on profile %s (%s) stored without a notification",
            report.get("report_id"),
            profile.get("profile_id"),
            report.get("reason", ""),
        )
        return False

    subject, html_body = report_email(report, profile, reporter_email, conversation)
    try:
        resp = httpx.post(
            RESEND_API_URL,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json={
                "from": settings.email_from,
                "to": [settings.moderation_email],
                # Replying goes straight to the person who filed it, which is
                # the "timely response to concerns" guideline 1.2 asks for.
                **({"reply_to": [reporter_email]} if reporter_email else {}),
                "subject": subject,
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
