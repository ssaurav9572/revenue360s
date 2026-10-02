from __future__ import annotations
import hashlib
import hmac
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parent.parent
APP_DIR = Path(__file__).resolve().parent
if str(APP_DIR) not in sys.path:
    sys.path.insert(0, str(APP_DIR))

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, RedirectResponse, Response
from fastapi.staticfiles import StaticFiles

from auth import auth_router, company_router
from ad_platforms import router as ad_platforms_router
import learning
from db import env, env_flag, init_db, insert, one, public_url
from communication_channel import email_router, inbox_router, sms_router, templates_router, whatsapp_router
from engine import PIXEL, agent_router, audience_router, campaign_router, overview_router, process_inbound, sequences_router, workflows_router
from leads import router as leads_router
from settings import accounts_router, router as settings_router
from social_media import ads_router, social_router
from social_automations import handle_meta_change, router as social_automations_router

FRONTEND = ROOT / "frontend"

app = FastAPI(title="Revenue360s")

app.include_router(auth_router)
app.include_router(overview_router)
app.include_router(inbox_router)
app.include_router(leads_router)
app.include_router(sequences_router)
app.include_router(templates_router)
app.include_router(social_router)
app.include_router(social_automations_router)
app.include_router(workflows_router)
app.include_router(email_router)
app.include_router(sms_router)
app.include_router(whatsapp_router)
app.include_router(ads_router)
app.include_router(ad_platforms_router)
app.include_router(company_router)
app.include_router(settings_router)
app.include_router(accounts_router)
app.include_router(audience_router)
app.include_router(campaign_router)
app.include_router(agent_router)


@app.on_event("startup")
def _start() -> None:
    init_db()
    learning.ensure_tables()


@app.get("/health")
def health() -> dict:
    return {"ok": True, "db": env("DB_NAME", "revenue360")}


@app.get("/webhooks/meta")
def meta_verify(request: Request):
    params = dict(request.query_params)
    if params.get("hub.mode") == "subscribe" and params.get("hub.verify_token") == env("META_WEBHOOK_VERIFY_TOKEN", "revenue360s-verify"):
        return Response(content=params.get("hub.challenge", ""), media_type="text/plain")
    raise HTTPException(403, "verify token mismatch")


def verify_meta_webhook_signature(raw_body: bytes, signature: str | None) -> bool:
    secret = env("META_APP_SECRET", "").strip()
    if not secret:
        # Fail closed: unsigned webhooks are accepted only when explicitly allowed (local dev).
        return env_flag("R360_ALLOW_UNSIGNED_WEBHOOKS")
    if not signature:
        return False
    digest = hmac.new(secret.encode("utf-8"), raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(f"sha256={digest}", signature.strip())


@app.post("/webhooks/meta")
async def meta_inbound(request: Request) -> dict:
    raw_body = await request.body()
    signature = request.headers.get("x-hub-signature-256")
    if not verify_meta_webhook_signature(raw_body, signature):
        raise HTTPException(403, "webhook signature mismatch")
    payload = await request.json()
    handled = 0
    object_type = str(payload.get("object") or "").lower()
    for entry in payload.get("entry") or []:
        entry_id = str(entry.get("id") or "")
        for change in entry.get("changes") or []:
            value = change.get("value") or {}
            if handle_meta_change(object_type, entry_id, str(change.get("field") or ""), value):
                handled += 1
            phone_number_id = str((value.get("metadata") or {}).get("phone_number_id") or "")
            connection = one("SELECT workspace_id FROM whatsapp_connections WHERE phone_number_id = ? LIMIT 1", (phone_number_id,)) if phone_number_id else None
            if not connection:
                continue
            for message in value.get("messages") or []:
                sender = str(message.get("from") or "")
                text = str(((message.get("text") or {}).get("body")) or "")
                if sender and text:
                    process_inbound(connection["workspace_id"], "whatsapp", sender, text)
                    handled += 1
    return {"ok": True, "handled": handled}


@app.get("/t/o/{message_id}.gif")
def track_open(message_id: str):
    message = one("SELECT * FROM messages WHERE id = ?", (message_id.replace(".gif", ""),))
    if message:
        exists = one("SELECT id FROM tracking_events WHERE message_id = ? AND event_type = 'open' LIMIT 1", (message["id"],))
        if not exists:
            insert(
                "tracking_events",
                {"message_id": message["id"], "lead_id": message.get("lead_id") or "", "event_type": "open", "url": ""},
                message["workspace_id"],
            )
    return Response(content=PIXEL, media_type="image/gif", headers={"Cache-Control": "no-store"})


@app.get("/t/c/{message_id}")
def track_click(message_id: str, u: str = ""):
    default = public_url()
    message = one("SELECT * FROM messages WHERE id = ?", (message_id,))
    target = (u or "").strip()
    # Only redirect to a link that was actually in the message we sent (no open redirect, external links work).
    if not message or not target.startswith(("http://", "https://")) or target not in (message.get("body") or ""):
        return RedirectResponse(default, status_code=302)
    insert(
        "tracking_events",
        {"message_id": message["id"], "lead_id": message.get("lead_id") or "", "event_type": "click", "url": target},
        message["workspace_id"],
    )
    try:
        learning.record_outcome(message["workspace_id"], message.get("lead_id") or "", "click")
    except Exception:
        pass
    return RedirectResponse(target, status_code=302)


app.mount("/static", StaticFiles(directory=FRONTEND), name="static")


@app.get("/favicon.ico", include_in_schema=False)
def favicon():
    return Response(status_code=204)


@app.get("/")
def root():
    return FileResponse(FRONTEND / "index.html", headers={"Cache-Control": "no-store"})
