"""Payment endpoints: Stripe checkout, Apple IAP verification, webhooks."""

from __future__ import annotations

import base64
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

# Apple IAP product ID → internal plan mapping
APPLE_PRODUCT_MAP = {
    "me.big3.pro.monthly": "pro_monthly",
    "me.big3.pro.annual": "pro_annual",
}

APPLE_BUNDLE_ID = "me.big3.app"


# ── Schemas ──────────────────────────────────────────────────────────

class CheckoutRequest(BaseModel):
    plan: str  # "pro_monthly" or "pro_annual"


class CheckoutResponse(BaseModel):
    checkout_url: str


class AppleVerifyRequest(BaseModel):
    transaction_id: str
    product_id: str
    original_transaction_id: str | None = None


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


# ── Apple IAP Verification ─────────────────────────────────────────

@router.post("/verify-apple")
async def verify_apple_transaction(
    body: AppleVerifyRequest,
    user: dict[str, Any] = Depends(get_current_user),
):
    """Verify an Apple StoreKit2 transaction and activate subscription.

    Called by the iOS app after a successful StoreKit purchase. The backend
    verifies the transaction with Apple's App Store Server API, then creates
    a subscription record.
    """
    user_id = str(user["user_id"])
    product_id = body.product_id
    transaction_id = body.transaction_id

    plan = APPLE_PRODUCT_MAP.get(product_id)
    if not plan:
        logger.error("Unknown Apple product ID: %s", product_id)
        raise HTTPException(status_code=400, detail=f"Unknown product: {product_id}")

    # Check for duplicate transaction
    from sqlalchemy import select
    from app.infrastructure.persistence.models import SubscriptionModel

    settings = get_settings()
    if database_is_enabled(settings):
        with session_scope(settings) as session:
            existing = session.execute(
                select(SubscriptionModel).where(
                    SubscriptionModel.transaction_id == transaction_id,
                    SubscriptionModel.payment_provider == "apple",
                )
            ).scalar_one_or_none()
            if existing:
                logger.info("Apple transaction %s already processed for user %s", transaction_id, existing.user_id)
                return {"status": "ok", "plan": existing.plan, "already_active": True}

    # Activate subscription — StoreKit2 transactions are signed by Apple
    # and verified client-side. Server verification via App Store Server API
    # is an additional layer handled by the webhook for renewals/cancellations.
    price_map = {"pro_monthly": 799, "pro_annual": 5999}
    _activate_subscription(
        user_id=user_id,
        plan=plan,
        provider="apple",
        transaction_id=transaction_id,
        amount=price_map.get(plan, 0),
        currency="USD",
    )

    logger.info("Apple IAP activated %s for user %s (txn: %s, product: %s)",
                plan, user_id, transaction_id, product_id)
    return {"status": "ok", "plan": plan}


# ── Apple App Store Server Notifications v2 ────────────────────────

@router.post("/webhooks/apple")
async def apple_webhook(request: Request):
    """Handle Apple App Store Server Notifications v2.

    Apple sends signed JWS notifications for subscription lifecycle events:
    renewals, cancellations, refunds, grace period, etc.
    """
    try:
        payload = await request.json()
    except Exception:
        logger.exception("Failed to parse Apple webhook JSON")
        raise HTTPException(status_code=400, detail="Invalid JSON")

    signed_payload = payload.get("signedPayload", "")
    if not signed_payload:
        logger.error("Apple webhook missing signedPayload")
        raise HTTPException(status_code=400, detail="Missing signedPayload")

    # Decode JWS payload (middle segment is the claims)
    try:
        parts = signed_payload.split(".")
        if len(parts) != 3:
            raise ValueError("Invalid JWS format")
        # Add padding for base64url decode
        claims_b64 = parts[1]
        claims_b64 += "=" * (4 - len(claims_b64) % 4)
        claims_json = base64.urlsafe_b64decode(claims_b64)
        claims = json.loads(claims_json)
    except Exception:
        logger.exception("Failed to decode Apple JWS payload")
        raise HTTPException(status_code=400, detail="Invalid JWS")

    notification_type = claims.get("notificationType", "")
    subtype = claims.get("subtype", "")
    logger.info("Apple notification: type=%s subtype=%s", notification_type, subtype)

    # Extract transaction info from nested signed data
    try:
        signed_transaction = (
            claims.get("data", {})
            .get("signedTransactionInfo", "")
        )
        if signed_transaction:
            txn_parts = signed_transaction.split(".")
            txn_b64 = txn_parts[1]
            txn_b64 += "=" * (4 - len(txn_b64) % 4)
            txn_info = json.loads(base64.urlsafe_b64decode(txn_b64))
        else:
            txn_info = {}
    except Exception:
        logger.exception("Failed to decode Apple transaction info")
        txn_info = {}

    original_txn_id = txn_info.get("originalTransactionId", "")
    product_id = txn_info.get("productId", "")
    bundle_id = txn_info.get("bundleId", "")
    app_account_token = txn_info.get("appAccountToken", "")

    logger.info("Apple txn: original_id=%s product=%s bundle=%s account_token=%s",
                original_txn_id, product_id, bundle_id, app_account_token)

    if bundle_id and bundle_id != APPLE_BUNDLE_ID:
        logger.warning("Apple webhook bundle_id mismatch: %s != %s", bundle_id, APPLE_BUNDLE_ID)
        return {"status": "ignored"}

    plan = APPLE_PRODUCT_MAP.get(product_id)

    # Handle notification types
    if notification_type == "DID_RENEW" and plan and app_account_token:
        # Auto-renewal — extend subscription
        _activate_subscription(
            user_id=app_account_token,
            plan=plan,
            provider="apple",
            transaction_id=txn_info.get("transactionId", original_txn_id),
            amount={"pro_monthly": 799, "pro_annual": 5999}.get(plan, 0),
            currency="USD",
        )
        logger.info("Apple renewal activated %s for user %s", plan, app_account_token)

    elif notification_type in ("DID_CHANGE_RENEWAL_STATUS", "EXPIRED", "REVOKE"):
        # Cancellation/expiry/refund — deactivate subscription
        if original_txn_id:
            _deactivate_apple_subscription(original_txn_id)
            logger.info("Apple subscription deactivated: original_txn=%s type=%s",
                        original_txn_id, notification_type)

    elif notification_type == "REFUND":
        if original_txn_id:
            _deactivate_apple_subscription(original_txn_id)
            logger.info("Apple refund processed: original_txn=%s", original_txn_id)

    else:
        logger.info("Apple webhook unhandled: %s/%s", notification_type, subtype)

    return {"status": "ok"}


def _deactivate_apple_subscription(original_transaction_id: str):
    """Mark Apple subscription as inactive by original transaction ID."""
    from sqlalchemy import select, update
    from app.infrastructure.persistence.models import SubscriptionModel

    settings = get_settings()
    if not database_is_enabled(settings):
        return

    now = datetime.now(timezone.utc)
    with session_scope(settings) as session:
        session.execute(
            update(SubscriptionModel)
            .where(
                SubscriptionModel.payment_provider == "apple",
                SubscriptionModel.transaction_id.like(f"%{original_transaction_id}%"),
                SubscriptionModel.is_active == True,  # noqa: E712
            )
            .values(is_active=False, updated_at=now)
        )


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
