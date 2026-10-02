import importlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"
for value in (str(ROOT), str(BACKEND)):
    if value not in sys.path:
        sys.path.insert(0, value)

import pytest

engine = importlib.import_module("backend.engine")
main_module = importlib.import_module("backend.main")


def test_find_or_create_lead_update_is_workspace_scoped(monkeypatch):
    calls = []

    monkeypatch.setattr(engine, "find_lead", lambda *args, **kwargs: {"id": "lead-1", "name": "", "email": "", "phone": ""})
    monkeypatch.setattr(engine, "execute", lambda sql, params=(): calls.append((sql, params)))
    monkeypatch.setattr(engine, "one", lambda sql, params=(): {"id": "lead-1", "name": "Alice", "email": "alice@example.com", "phone": "1234567890"})

    engine.find_or_create_lead("ws-1", "Alice", "1234567890", "alice@example.com")

    assert any("WHERE id = ? AND workspace_id = ?" in sql for sql, _ in calls)


def test_process_inbound_unsubscribed_update_is_workspace_scoped(monkeypatch):
    calls = []

    monkeypatch.setattr(engine, "find_or_create_lead", lambda *args, **kwargs: ({"id": "lead-1", "last_contacted_at": "2024-01-01T00:00:00+00:00"}, False))
    monkeypatch.setattr(engine, "add_suppression", lambda *args, **kwargs: None)
    monkeypatch.setattr(engine, "execute", lambda sql, params=(): calls.append((sql, params)))
    monkeypatch.setattr(engine, "stop_sequences", lambda *args, **kwargs: None)
    monkeypatch.setattr(engine, "insert", lambda *args, **kwargs: None)
    monkeypatch.setattr(engine, "execute_event", lambda *args, **kwargs: 0)
    monkeypatch.setattr(engine, "matching_sequences", lambda *args, **kwargs: [])

    engine.process_inbound("ws-1", "email", "alice@example.com", "stop")

    assert any("UPDATE leads SET stage = 'unsubscribed'" in sql and "workspace_id = ?" in sql for sql, _ in calls)


def test_track_click_rejects_open_redirect(monkeypatch):
    calls = []

    monkeypatch.setattr(main_module, "one", lambda *args, **kwargs: {"id": "msg-1", "workspace_id": "ws-1", "lead_id": "lead-1"})
    monkeypatch.setattr(main_module, "insert", lambda *args, **kwargs: calls.append((args, kwargs)))

    response = main_module.track_click("msg-1", u="//evil.example")

    assert response.status_code == 302
    assert response.headers["location"] == "https://revenue360s.com"


def test_process_due_claims_enrollments_before_send(monkeypatch):
    calls = []
    enrollment = {
        "id": "enr-1",
        "workspace_id": "ws-1",
        "sequence_id": "seq-1",
        "lead_id": "lead-1",
        "current_step": 0,
        "status": "active",
        "next_run_at": "2024-01-01T00:00:00+00:00",
        "created_at": "2024-01-01T00:00:00+00:00",
    }

    def fake_one(sql, params=()):
        if "FROM sequences" in sql:
            return {"id": "seq-1", "enabled": 1, "stop_on_reply": 0, "workspace_id": "ws-1"}
        if "FROM leads" in sql:
            return {"id": "lead-1", "workspace_id": "ws-1", "email": "person@example.com", "phone": "1234567890", "stage": "contacted"}
        if "FROM sequence_steps" in sql:
            return {"id": "step-1", "sequence_id": "seq-1", "step_order": 1, "channel": "email", "delay_hours": 1, "account_id": ""}
        return None

    monkeypatch.setattr(engine, "query", lambda *args, **kwargs: [enrollment])
    monkeypatch.setattr(engine, "one", fake_one)
    monkeypatch.setattr(engine, "execute", lambda sql, params=(): calls.append((sql, params)))
    monkeypatch.setattr(engine, "is_suppressed", lambda *args, **kwargs: False)
    monkeypatch.setattr(engine, "send_channel", lambda *args, **kwargs: True)

    engine.process_due("ws-1", limit=10)

    assert any("UPDATE sequence_enrollments SET status = 'processing'" in sql for sql, _ in calls)
