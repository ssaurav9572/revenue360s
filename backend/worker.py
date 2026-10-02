from __future__ import annotations
import json
import re
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

import requests

APP_DIR = Path(__file__).resolve().parent
if str(APP_DIR) not in sys.path:
    sys.path.insert(0, str(APP_DIR))

import learning
from social_automations import retry_comment_events
from db import env, execute, init_db, insert, json_text, now_iso, one, query, reveal
from engine import process_agent_due, process_due, process_due_campaigns
from ad_platforms import run_optimization_rules


def _publish_linkedin(account: dict, caption: str, media: str = "") -> dict:
    connection = reveal("social_accounts", account) or {}
    token = connection.get("access_token") or ""
    if not token:
        raise ValueError("LinkedIn account has no access token.")
    if media:
        raise ValueError("LinkedIn image and video upload is not connected yet; queue this as a text-only post.")
    author = str(connection.get("handle") or "").strip()
    try:
        settings = json.loads(connection.get("settings") or "{}")
    except (TypeError, json.JSONDecodeError):
        settings = {}
    author = str(settings.get("author_urn") or author).strip()
    if not re.fullmatch(r"urn:li:organization:[0-9]+|urn:li:person:[A-Za-z0-9_-]+", author):
        raise ValueError("Use a LinkedIn author URN such as urn:li:organization:12345 or urn:li:person:<member-id>.")
    if not caption.strip() or len(caption) > 3000:
        raise ValueError("LinkedIn text posts must contain 1 to 3,000 characters.")
    version = str(settings.get("api_version") or env("LINKEDIN_MARKETING_VERSION", "202608"))
    try:
        response = requests.post(
            "https://api.linkedin.com/rest/posts",
            headers={
                "Authorization": f"Bearer {token}",
                "Linkedin-Version": version,
                "X-Restli-Protocol-Version": "2.0.0",
                "Content-Type": "application/json",
            },
            json={
                "author": author,
                "commentary": caption,
                "visibility": "PUBLIC",
                "distribution": {
                    "feedDistribution": "MAIN_FEED",
                    "targetEntities": [],
                    "thirdPartyDistributionChannels": [],
                },
                "lifecycleState": "PUBLISHED",
                "isReshareDisabledByAuthor": False,
            },
            timeout=25,
        )
    except requests.RequestException as error:
        raise ValueError(f"LinkedIn request failed ({type(error).__name__}).") from error
    if not response.ok:
        raise ValueError(f"LinkedIn returned HTTP {response.status_code}.")
    return {"post_id": response.headers.get("x-restli-id", ""), "status": "published"}


def _account_settings(account: dict) -> dict:
    try:
        settings = json.loads(account.get("settings") or "{}")
        return settings if isinstance(settings, dict) else {}
    except (TypeError, json.JSONDecodeError):
        return {}


def _publish_instagram_reel(account: dict, post: dict, attempt: dict) -> dict:
    connection = reveal("social_accounts", account) or {}
    token = str(connection.get("access_token") or "")
    user_id = str(connection.get("handle") or "")
    if not token or not user_id:
        raise ValueError("Instagram account has no professional account ID or access token.")
    video_url = str(post.get("media") or "").strip()
    if not video_url or urlparse(video_url).scheme != "https" or not urlparse(video_url).netloc:
        raise ValueError("Instagram Reels need a public HTTPS video URL that Meta can fetch.")
    settings = _account_settings(connection)
    version = str(settings.get("api_version") or env("META_GRAPH_API_VERSION", "v25.0")).strip("/")
    host = "graph.instagram.com" if str(settings.get("login_type") or "facebook").lower() == "instagram" else "graph.facebook.com"
    base = f"https://{host}/{version}"
    headers = {"Authorization": f"Bearer {token}"}
    creation_id = str(attempt.get("provider_ref") or "")
    if not creation_id:
        try:
            response = requests.post(
                f"{base}/{user_id}/media",
                headers=headers,
                data={"media_type": "REELS", "video_url": video_url, "caption": str(post.get("caption") or ""), "share_to_feed": "true"},
                timeout=30,
            )
        except requests.RequestException as error:
            raise ValueError(f"Instagram container request failed ({type(error).__name__}).") from error
        if not response.ok:
            raise ValueError(f"Instagram returned HTTP {response.status_code} while creating the Reel container.")
        creation_id = str((response.json() or {}).get("id") or "")
        if not creation_id:
            raise ValueError("Instagram did not return a Reel container ID.")
        execute(
            "UPDATE social_publish_attempts SET provider_ref = ?, attempts = attempts + 1, detail = ?, updated_at = ? WHERE id = ?",
            (creation_id, "Instagram is processing the Reel video.", now_iso(), attempt["id"]),
        )
        return {"status": "pending", "detail": "Instagram is processing the Reel video."}

    try:
        response = requests.get(
            f"{base}/{creation_id}", headers=headers,
            params={"fields": "status_code,status"}, timeout=20,
        )
    except requests.RequestException as error:
        raise ValueError(f"Instagram status request failed ({type(error).__name__}).") from error
    if not response.ok:
        raise ValueError(f"Instagram returned HTTP {response.status_code} while checking Reel processing.")
    state = str((response.json() or {}).get("status_code") or "").upper()
    if state in {"IN_PROGRESS", "STARTED"}:
        if int(attempt.get("attempts") or 0) >= 120:
            raise ValueError("Instagram Reel processing did not finish after 120 checks.")
        execute(
            "UPDATE social_publish_attempts SET attempts = attempts + 1, detail = ?, updated_at = ? WHERE id = ?",
            (f"Instagram Reel processing: {state}.", now_iso(), attempt["id"]),
        )
        return {"status": "pending", "detail": f"Instagram Reel processing: {state}."}
    if state != "FINISHED":
        raise ValueError(f"Instagram Reel processing ended with status {state or 'unknown'}.")
    try:
        published = requests.post(
            f"{base}/{user_id}/media_publish", headers=headers,
            data={"creation_id": creation_id}, timeout=30,
        )
    except requests.RequestException as error:
        raise ValueError(f"Instagram publish request failed ({type(error).__name__}).") from error
    if not published.ok:
        raise ValueError(f"Instagram returned HTTP {published.status_code} while publishing the Reel.")
    return {"status": "published", "post_id": str((published.json() or {}).get("id") or "")}


def _publish_threads_text(account: dict, post: dict, attempt: dict) -> dict:
    connection = reveal("social_accounts", account) or {}
    token = str(connection.get("access_token") or "")
    user_id = str(connection.get("handle") or "")
    if not token or not user_id:
        raise ValueError("Threads account has no user ID or access token.")
    if post.get("media"):
        raise ValueError("Threads scheduled publishing currently supports text posts only.")
    settings = _account_settings(connection)
    version = str(settings.get("api_version") or "v1.0").strip("/")
    base = f"https://graph.threads.net/{version}"
    creation_id = str(attempt.get("provider_ref") or "")
    if not creation_id:
        try:
            created = requests.post(
                f"{base}/{user_id}/threads",
                data={"media_type": "TEXT", "text": str(post.get("caption") or ""), "access_token": token},
                timeout=25,
            )
        except requests.RequestException as error:
            raise ValueError(f"Threads request failed ({type(error).__name__}).") from error
        if not created.ok:
            raise ValueError(f"Threads returned HTTP {created.status_code} while creating the post.")
        creation_id = str((created.json() or {}).get("id") or "")
        if not creation_id:
            raise ValueError("Threads did not return a post container ID.")
        execute(
            "UPDATE social_publish_attempts SET provider_ref = ?, attempts = attempts + 1, detail = ?, updated_at = ? WHERE id = ?",
            (creation_id, "Threads post container created.", now_iso(), attempt["id"]),
        )
    try:
        published = requests.post(
            f"{base}/{user_id}/threads_publish",
            data={"creation_id": creation_id, "access_token": token}, timeout=25,
        )
    except requests.RequestException as error:
        raise ValueError(f"Threads publish request failed ({type(error).__name__}).") from error
    if not published.ok:
        raise ValueError(f"Threads returned HTTP {published.status_code} while publishing.")
    return {"status": "published", "post_id": str((published.json() or {}).get("id") or "")}


def process_scheduled_posts(limit: int = 30) -> dict:
    """Publish supported due posts and resume provider media containers on later worker ticks."""
    due = query(
        "SELECT * FROM scheduled_posts WHERE status = 'queued' AND scheduled_at <= ? ORDER BY scheduled_at ASC LIMIT ?",
        (now_iso(), limit),
    )
    published = failed = partial = queued = 0
    for post in due:
        try:
            account_ids = json.loads(post.get("account_ids") or "[]")
        except (TypeError, json.JSONDecodeError):
            account_ids = []
        if not isinstance(account_ids, list):
            account_ids = []
        outcomes = []
        caption = str(post.get("caption") or "")
        for account_id in account_ids:
            account = one(
                "SELECT * FROM social_accounts WHERE id = ? AND workspace_id = ?",
                (account_id, post["workspace_id"]),
            )
            if not account:
                outcomes.append({"account_id": account_id, "status": "failed", "detail": "social account unavailable"})
                continue
            attempt = one("SELECT * FROM social_publish_attempts WHERE scheduled_post_id = ? AND account_id = ?", (post["id"], account_id))
            if not attempt:
                insert("social_publish_attempts", {
                    "scheduled_post_id": post["id"], "account_id": account_id,
                    "platform": account.get("platform") or "", "status": "pending", "updated_at": now_iso(),
                }, post["workspace_id"])
                attempt = one("SELECT * FROM social_publish_attempts WHERE scheduled_post_id = ? AND account_id = ?", (post["id"], account_id))
            if attempt.get("status") in {"published", "failed"}:
                outcomes.append({"account_id": account_id, "platform": account.get("platform"), "status": attempt["status"], "post_id": attempt.get("response_id"), "detail": attempt.get("detail") or ""})
                continue
            try:
                platform = account.get("platform")
                if platform == "linkedin":
                    result = _publish_linkedin(account, caption, str(post.get("media") or ""))
                elif platform == "instagram":
                    result = _publish_instagram_reel(account, post, attempt)
                elif platform == "threads":
                    result = _publish_threads_text(account, post, attempt)
                else:
                    raise ValueError("Live publishing adapter is not connected for this platform.")
                state = result.get("status") or "failed"
                if state == "published":
                    execute("UPDATE social_publish_attempts SET status = 'published', response_id = ?, attempts = attempts + 1, detail = '', updated_at = ? WHERE id = ?", (result.get("post_id") or "", now_iso(), attempt["id"]))
                else:
                    execute("UPDATE social_publish_attempts SET status = 'pending', detail = ?, updated_at = ? WHERE id = ?", (result.get("detail") or "Provider processing.", now_iso(), attempt["id"]))
                outcomes.append({"account_id": account_id, "platform": platform, **result})
            except ValueError as error:
                execute("UPDATE social_publish_attempts SET status = 'failed', attempts = attempts + 1, detail = ?, updated_at = ? WHERE id = ?", (str(error)[:500], now_iso(), attempt["id"]))
                outcomes.append({"account_id": account_id, "platform": account.get("platform"), "status": "failed", "detail": str(error)[:240]})
        successes = sum(1 for outcome in outcomes if outcome.get("status") == "published")
        pending = sum(1 for outcome in outcomes if outcome.get("status") == "pending")
        if pending:
            status = "queued"
            queued += 1
        elif successes == len(account_ids) and successes:
            status = "published"
            published += 1
        elif successes:
            status = "partial"
            partial += 1
        else:
            status = "failed"
            failed += 1
        if not account_ids:
            outcomes = [{"status": "failed", "detail": "missing social account selection"}]
        execute(
            "UPDATE scheduled_posts SET status = ?, detail = ? WHERE id = ? AND workspace_id = ?",
            (status, json.dumps(outcomes, ensure_ascii=False), post["id"], post["workspace_id"]),
        )
    return {"scanned": len(due), "published": published, "partial": partial, "queued": queued, "failed": failed}

def run_once() -> dict:
    init_db()
    result = process_due()
    campaign_result = process_due_campaigns()
    agent_result = process_agent_due()
    scheduled_result = process_scheduled_posts()
    result["social_comment_retries"] = retry_comment_events()
    optimization_result = run_optimization_rules()
    result["ad_rules_checked"] = optimization_result.get("checked", 0)
    result["ad_rules_paused"] = optimization_result.get("paused", 0)
    result["ad_rules_failed"] = optimization_result.get("failed", 0)
    result["campaigns"] = campaign_result.get("processed", 0)
    result["agent"] = agent_result.get("advanced", 0)
    result["published"] = scheduled_result.get("published", 0)
    result["partial"] = scheduled_result.get("partial", 0)
    result["queued"] = scheduled_result.get("queued", 0)
    result["failed"] = scheduled_result.get("failed", 0)
    try:
        result["learning"] = learning.learn_nightly()
    except Exception as error:  # learning must never stop the send loop
        result["learning"] = {"error": str(error)}
    return result

def main() -> None:
    print("Revenue360s worker started. Ctrl+C to stop.")
    while True:
        try:
            print(time.strftime("%Y-%m-%d %H:%M:%S"), run_once())
        except Exception as error:
            print("worker error", error)
        time.sleep(30)

if __name__ == "__main__":
    main()
