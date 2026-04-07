"""Stripe payment endpoints: checkout session creation + webhook handler."""

from __future__ import annotations

import hashlib
import hmac
import json
import logging
import os
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.api.auth import get_current_user
from app.core.config import get_settings
from app.infrastructure.persistence.session import database_is_enabled, session_scope

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/payments", tags=["payments"])


# ── Schemas ──────────────────────────────────────────────────────────

class CheckoutRequest(BaseModel):
    plan: str  # "pro_monthly" or "pro_annual"


class CheckoutResponse(BaseModel):
    checkout_url: str


# ── Helpers ──────────────────────────────────────────────────────────

def _get_stripe():
    """Lazy import stripe to avoid hard dependency."""
    try:
        import stripe
        stripe.api_key = os.environ.get("STRIPE_SECRET_KEY", "")
        return stripe
    except ImportError:
        logger.error("stripe package not installed")
        raise HTTPException(status_code=500, detail="Payment system unavailable")


def _get_price_id(plan: str) -> str:
    """Map plan name to Stripe price ID."""
    prices = {
        "pro_monthly": os.environ.get("STRIPE_PRICE_PRO_MONTHLY", ""),
        "pro_annual": os.environ.get("STRIPE_PRICE_PRO_ANNUAL", ""),
    }
    price_id = prices.get(plan)
    if not price_id:
        logger.error("Stripe price not configured for plan %s. Check STRIPE_PRICE_PRO_MONTHLY/ANNUAL env vars.", plan)
        raise HTTPException(status_code=500, detail=f"Payment not configured for plan: {plan}. Please contact support.")
    return price_id


def _plan_days(plan: str) -> int:
    """Return subscription duration in days."""
    return {"pro_monthly": 30, "pro_annual": 365, "lifetime": 36500}.get(plan, 30)


def _activate_subscription(
    user_id: str,
    plan: str,
    provider: str,
    transaction_id: str,
    amount: int,
    currency: str = "USD",
):
    """Create subscription record in database."""
    from app.infrastructure.persistence.models import SubscriptionModel

    settings = get_settings()
    if not database_is_enabled(settings):
        logger.error("Cannot activate subscription: database not enabled")
        return

    now = datetime.now(timezone.utc)
    expires = now + timedelta(days=_plan_days(plan))

    with session_scope(settings) as session:
        sub = SubscriptionModel(
            id=str(uuid.uuid4()),
            user_id=user_id,
            plan=plan,
            payment_provider=provider,
            transaction_id=transaction_id,
            amount=amount,
            currency=currency,
            started_at=now,
            expires_at=expires,
            is_active=True,
            created_at=now,
            updated_at=now,
        )
        session.add(sub)

    logger.info("Activated %s for user %s via %s (txn: %s)", plan, user_id, provider, transaction_id)


# ── Stripe Checkout ──────────────────────────────────────────────────

@router.post("/create-checkout", response_model=CheckoutResponse)
def create_checkout(
    body: CheckoutRequest,
    user: dict[str, Any] = Depends(get_current_user),
):
    """Create a Stripe Checkout session for Pro subscription."""
    stripe = _get_stripe()
    price_id = _get_price_id(body.plan)

    try:
        session = stripe.checkout.Session.create(
            mode="subscription",
            line_items=[{"price": price_id, "quantity": 1}],
            client_reference_id=str(user["user_id"]),
            customer_email=user.get("email"),
            allow_promotion_codes=True,
            success_url="https://big3.me/?payment=success",
            cancel_url="https://big3.me/?payment=cancel",
            metadata={
                "user_id": str(user["user_id"]),
                "plan": body.plan,
            },
        )
        return {"checkout_url": session.url}
    except Exception:
        logger.exception("Failed to create Stripe checkout session")
        raise HTTPException(status_code=500, detail="Failed to create checkout session")


# ── Stripe Webhook ───────────────────────────────────────────────────

@router.post("/webhooks/stripe")
async def stripe_webhook(request: Request):
    """Handle Stripe webhook events (checkout.session.completed)."""
    stripe = _get_stripe()
    payload = await request.body()
    sig_header = request.headers.get("stripe-signature", "")
    webhook_secret = os.environ.get("STRIPE_WEBHOOK_SECRET", "")

    logger.info("Stripe webhook received, payload_len=%d, sig=%s, secret=%s",
                len(payload), bool(sig_header), bool(webhook_secret))

    if not webhook_secret:
        logger.error("STRIPE_WEBHOOK_SECRET not configured")
        raise HTTPException(status_code=500, detail="Webhook not configured")

    # Verify signature
    try:
        stripe.Webhook.construct_event(payload, sig_header, webhook_secret)
    except Exception as exc:
        logger.exception("Stripe webhook signature verification failed: %s", exc)
        raise HTTPException(status_code=400, detail="Invalid signature")

    # Parse raw JSON — avoids all SDK version compatibility issues
    try:
        data = json.loads(payload)
    except Exception:
        logger.exception("Failed to parse webhook JSON payload")
        raise HTTPException(status_code=400, detail="Invalid JSON")

    event_type = data.get("type", "")
    logger.info("Stripe webhook event: %s", event_type)

    try:
        if event_type == "checkout.session.completed":
            session_obj = data.get("data", {}).get("object", {})
            user_id = session_obj.get("client_reference_id") or session_obj.get("metadata", {}).get("user_id")
            plan = session_obj.get("metadata", {}).get("plan", "pro_monthly")
            session_id = session_obj.get("id", "")

            logger.info("Checkout session: id=%s, user_id=%s, plan=%s", session_id, user_id, plan)

            if not user_id:
                logger.error("No user_id in Stripe checkout session: %s", session_id)
                return {"status": "error", "detail": "No user_id"}

            amount = session_obj.get("amount_total", 0)
            currency = (session_obj.get("currency") or "usd").upper()

            _activate_subscription(
                user_id=user_id,
                plan=plan,
                provider="stripe",
                transaction_id=session_id,
                amount=amount,
                currency=currency,
            )
            logger.info("Activated %s for user %s (txn: %s)", plan, user_id, session_id)

        elif event_type == "customer.subscription.deleted":
            sub_id = data.get("data", {}).get("object", {}).get("id", "")
            logger.info("Stripe subscription cancelled: %s", sub_id)

    except Exception:
        logger.exception("Failed to process Stripe webhook event %s", event_type)
        # Return 200 so Stripe stops retrying — we log the error for debugging
        return {"status": "error", "detail": "Processing failed"}

    return {"status": "ok"}


# ── bePaid Webhook (placeholder) ─────────────────────────────────────

@router.post("/webhooks/bepaid")
async def bepaid_webhook(request: Request):
    """Handle bePaid payment notification (CIS cards: MIR, Belkart)."""
    body = await request.json()

    tracking_id = body.get("transaction", {}).get("tracking_id", "")
    status = body.get("transaction", {}).get("status", "")

    if status != "successful":
        logger.info("bePaid non-success status: %s for tracking %s", status, tracking_id)
        return {"status": "ignored"}

    # tracking_id format: "user_<user_id>_plan_<plan>"
    parts = tracking_id.split("_")
    user_id = None
    plan = "pro_monthly"
    for i, part in enumerate(parts):
        if part == "user" and i + 1 < len(parts):
            user_id = parts[i + 1]
        if part == "plan" and i + 1 < len(parts):
            plan = parts[i + 1]

    if not user_id:
        logger.error("No user_id in bePaid tracking_id: %s", tracking_id)
        return {"status": "error"}

    amount = body.get("transaction", {}).get("amount", 0)
    currency = body.get("transaction", {}).get("currency", "USD")

    _activate_subscription(
        user_id=user_id,
        plan=plan,
        provider="bepaid",
        transaction_id=body.get("transaction", {}).get("uid", ""),
        amount=amount,
        currency=currency,
    )

    return {"status": "ok"}


# ── Stripe Customer Portal ──────────────────────────────────────────

@router.post("/customer-portal")
def create_customer_portal(
    user: dict[str, Any] = Depends(get_current_user),
):
    """Create a Stripe Customer Portal session for managing subscription."""
    stripe = _get_stripe()
    email = user.get("email")
    if not email:
        raise HTTPException(status_code=400, detail="No email on account")

    try:
        # Find customer by email
        customers = stripe.Customer.list(email=email, limit=1)
        if not customers.data:
            raise HTTPException(status_code=404, detail="No Stripe customer found")

        session = stripe.billing_portal.Session.create(
            customer=customers.data[0].id,
            return_url="https://big3.me/",
        )
        return {"portal_url": session.url}
    except HTTPException:
        raise
    except Exception:
        logger.exception("Failed to create customer portal session")
        raise HTTPException(status_code=500, detail="Failed to create portal session")
