CREATE TABLE IF NOT EXISTS workspaces (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    created_at VARCHAR(40) NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL DEFAULT '',
    full_name VARCHAR(255) NOT NULL DEFAULT '',
    google_sub VARCHAR(255) NOT NULL DEFAULT '',
    is_verified TINYINT NOT NULL DEFAULT 1,
    verification_token VARCHAR(64) NOT NULL DEFAULT '',
    verification_expires_at VARCHAR(40) NOT NULL DEFAULT '',
    reset_token VARCHAR(64) NOT NULL DEFAULT '',
    reset_expires_at VARCHAR(40) NOT NULL DEFAULT '',
    created_at VARCHAR(40) NOT NULL,
    CONSTRAINT fk_users_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS company_profiles (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    company_name VARCHAR(255) NOT NULL DEFAULT '',
    website VARCHAR(500) NOT NULL DEFAULT '',
    industry VARCHAR(255) NOT NULL DEFAULT '',
    offer TEXT,
    brand_voice TEXT,
    first_reply_mode VARCHAR(32) NOT NULL DEFAULT 'mine',
    created_at VARCHAR(40) NOT NULL,
    CONSTRAINT fk_company_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS company_documents (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    filename VARCHAR(255) NOT NULL,
    stored_path VARCHAR(500) NOT NULL,
    extracted_text LONGTEXT,
    created_at VARCHAR(40) NOT NULL,
    CONSTRAINT fk_docs_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS settings_kv (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    `key` VARCHAR(120) NOT NULL,
    value TEXT,
    created_at VARCHAR(40) NOT NULL,
    UNIQUE KEY uq_settings_ws_key (workspace_id, `key`),
    CONSTRAINT fk_settings_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS social_accounts (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    platform VARCHAR(40) NOT NULL,
    name VARCHAR(255) NOT NULL DEFAULT '',
    handle VARCHAR(255) NOT NULL,
    access_token TEXT,
    settings LONGTEXT,
    status VARCHAR(40) NOT NULL DEFAULT 'pending',
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL DEFAULT '',
    CONSTRAINT fk_social_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS whatsapp_connections (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    name VARCHAR(255) NOT NULL DEFAULT '',
    phone_number_id VARCHAR(120) NOT NULL DEFAULT '',
    business_account_id VARCHAR(120) NOT NULL DEFAULT '',
    access_token TEXT,
    settings LONGTEXT,
    status VARCHAR(40) NOT NULL DEFAULT 'sandbox',
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL DEFAULT '',
    CONSTRAINT fk_wa_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS leads (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    name VARCHAR(255) NOT NULL DEFAULT '',
    phone VARCHAR(64) NOT NULL DEFAULT '',
    phone_normalized VARCHAR(20) NOT NULL DEFAULT '',
    email VARCHAR(255) NOT NULL DEFAULT '',
    custom_fields LONGTEXT,
    source VARCHAR(80) NOT NULL DEFAULT 'manual',
    tags TEXT,
    status VARCHAR(40) NOT NULL DEFAULT 'new',
    stage VARCHAR(40) NOT NULL DEFAULT 'new',
    notes TEXT,
    last_contacted_at VARCHAR(40) NOT NULL DEFAULT '',
    created_at VARCHAR(40) NOT NULL,
    KEY idx_leads_ws (workspace_id, phone_normalized, email),
    CONSTRAINT fk_leads_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sequences (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    stop_on_reply TINYINT NOT NULL DEFAULT 1,
    enabled TINYINT NOT NULL DEFAULT 1,
    trigger_whatsapp TINYINT NOT NULL DEFAULT 1,
    trigger_sms TINYINT NOT NULL DEFAULT 0,
    trigger_email TINYINT NOT NULL DEFAULT 0,
    trigger_new_lead TINYINT NOT NULL DEFAULT 1,
    created_at VARCHAR(40) NOT NULL,
    CONSTRAINT fk_seq_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sequence_steps (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    sequence_id VARCHAR(36) NOT NULL,
    step_order INT NOT NULL,
    delay_hours DOUBLE NOT NULL DEFAULT 0,
    channel VARCHAR(20) NOT NULL,
    account_id VARCHAR(36) NOT NULL DEFAULT '',
    mode VARCHAR(20) NOT NULL DEFAULT 'mine',
    subject VARCHAR(255) NOT NULL DEFAULT '',
    body TEXT,
    created_at VARCHAR(40) NOT NULL,
    CONSTRAINT fk_seqsteps_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
    CONSTRAINT fk_seqsteps_seq FOREIGN KEY (sequence_id) REFERENCES sequences(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sequence_enrollments (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    sequence_id VARCHAR(36) NOT NULL,
    lead_id VARCHAR(36) NOT NULL,
    current_step INT NOT NULL DEFAULT 0,
    status VARCHAR(40) NOT NULL DEFAULT 'active',
    next_run_at VARCHAR(40) NOT NULL DEFAULT '',
    last_sent_at VARCHAR(40) NOT NULL DEFAULT '',
    created_at VARCHAR(40) NOT NULL,
    KEY idx_enroll_due (workspace_id, status, next_run_at),
    CONSTRAINT fk_enroll_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
    CONSTRAINT fk_enroll_seq FOREIGN KEY (sequence_id) REFERENCES sequences(id) ON DELETE CASCADE,
    CONSTRAINT fk_enroll_lead FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS messages (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    channel VARCHAR(20) NOT NULL,
    direction VARCHAR(20) NOT NULL,
    recipient VARCHAR(255) NOT NULL DEFAULT '',
    lead_id VARCHAR(36) NOT NULL DEFAULT '',
    sequence_id VARCHAR(36) NOT NULL DEFAULT '',
    step_id VARCHAR(36) NOT NULL DEFAULT '',
    account_id VARCHAR(36) NOT NULL DEFAULT '',
    campaign_id VARCHAR(36) NOT NULL DEFAULT '',
    subject VARCHAR(255) NOT NULL DEFAULT '',
    body TEXT,
    status VARCHAR(40) NOT NULL DEFAULT 'queued',
    created_at VARCHAR(40) NOT NULL,
    KEY idx_messages_ws (workspace_id, recipient, created_at),
    CONSTRAINT fk_msg_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS email_connections (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    name VARCHAR(255) NOT NULL DEFAULT '',
    provider VARCHAR(40) NOT NULL DEFAULT 'gmail_smtp',
    email_address VARCHAR(255) NOT NULL DEFAULT '',
    auth_type VARCHAR(40) NOT NULL DEFAULT 'smtp_app_password',
    smtp_host VARCHAR(120) NOT NULL DEFAULT 'smtp.gmail.com',
    smtp_port VARCHAR(10) NOT NULL DEFAULT '587',
    secret TEXT,
    refresh_token TEXT,
    settings LONGTEXT,
    status VARCHAR(40) NOT NULL DEFAULT 'sandbox',
    daily_cap INT NOT NULL DEFAULT 500,
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL DEFAULT '',
    CONSTRAINT fk_email_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sms_connections (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    name VARCHAR(255) NOT NULL DEFAULT '',
    provider VARCHAR(40) NOT NULL DEFAULT 'msg91',
    sender_id VARCHAR(40) NOT NULL DEFAULT '',
    entity_id VARCHAR(80) NOT NULL DEFAULT '',
    template_id VARCHAR(80) NOT NULL DEFAULT '',
    secret TEXT,
    settings LONGTEXT,
    status VARCHAR(40) NOT NULL DEFAULT 'sandbox',
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL DEFAULT '',
    CONSTRAINT fk_sms_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS templates (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    name VARCHAR(255) NOT NULL,
    channel VARCHAR(20) NOT NULL,
    subject VARCHAR(255) NOT NULL DEFAULT '',
    body TEXT,
    created_at VARCHAR(40) NOT NULL,
    KEY idx_tpl_ch (workspace_id, channel),
    CONSTRAINT fk_tpl_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS social_comment_automations (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    account_id VARCHAR(36) NOT NULL,
    platform VARCHAR(40) NOT NULL,
    name VARCHAR(255) NOT NULL DEFAULT '',
    post_id VARCHAR(255) NOT NULL DEFAULT '',
    keyword VARCHAR(255) NOT NULL DEFAULT '',
    template_id VARCHAR(36) NOT NULL,
    enabled TINYINT NOT NULL DEFAULT 1,
    executions INT NOT NULL DEFAULT 0,
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL DEFAULT '',
    KEY idx_social_auto_ws (workspace_id, enabled, platform),
    CONSTRAINT fk_social_auto_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS social_comment_events (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    account_id VARCHAR(36) NOT NULL,
    automation_id VARCHAR(36) NOT NULL,
    platform VARCHAR(40) NOT NULL,
    comment_id VARCHAR(255) NOT NULL,
    post_id VARCHAR(255) NOT NULL DEFAULT '',
    comment_text TEXT,
    response_id VARCHAR(255) NOT NULL DEFAULT '',
    status VARCHAR(40) NOT NULL DEFAULT 'pending',
    attempts INT NOT NULL DEFAULT 0,
    detail VARCHAR(500) NOT NULL DEFAULT '',
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL DEFAULT '',
    UNIQUE KEY uq_social_comment_event (workspace_id, platform, comment_id),
    KEY idx_social_comment_retry (status, updated_at),
    CONSTRAINT fk_social_comment_event_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS automations (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    name VARCHAR(255) NOT NULL,
    trigger_type VARCHAR(80) NOT NULL,
    keyword VARCHAR(255) NOT NULL DEFAULT '',
    action_type VARCHAR(80) NOT NULL,
    action_value TEXT,
    enabled TINYINT NOT NULL DEFAULT 1,
    executions INT NOT NULL DEFAULT 0,
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL DEFAULT '',
    KEY idx_auto_trig (trigger_type, enabled),
    CONSTRAINT fk_auto_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS automation_runs (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    automation_id VARCHAR(36) NOT NULL,
    action_type VARCHAR(80) NOT NULL,
    status VARCHAR(40) NOT NULL,
    detail TEXT,
    created_at VARCHAR(40) NOT NULL,
    CONSTRAINT fk_autorun_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
    CONSTRAINT fk_autorun_auto FOREIGN KEY (automation_id) REFERENCES automations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS events (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    event_type VARCHAR(80) NOT NULL,
    payload TEXT,
    created_at VARCHAR(40) NOT NULL,
    CONSTRAINT fk_events_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS ai_drafts (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    channel VARCHAR(20) NOT NULL,
    recipient VARCHAR(255) NOT NULL DEFAULT '',
    fetch_json TEXT,
    eval_json TEXT,
    draft_text TEXT,
    model VARCHAR(120) NOT NULL DEFAULT '',
    status VARCHAR(40) NOT NULL DEFAULT 'suggested',
    created_at VARCHAR(40) NOT NULL,
    CONSTRAINT fk_aidraft_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS suppressions (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    address VARCHAR(255) NOT NULL,
    channel VARCHAR(20) NOT NULL DEFAULT 'all',
    reason VARCHAR(80) NOT NULL DEFAULT 'unsubscribe',
    created_at VARCHAR(40) NOT NULL,
    KEY idx_supp (workspace_id, address, channel),
    CONSTRAINT fk_supp_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS tracking_events (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    message_id VARCHAR(36) NOT NULL DEFAULT '',
    lead_id VARCHAR(36) NOT NULL DEFAULT '',
    event_type VARCHAR(20) NOT NULL,
    url TEXT,
    created_at VARCHAR(40) NOT NULL,
    KEY idx_track (workspace_id, message_id, event_type),
    CONSTRAINT fk_track_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS saved_audiences (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    name VARCHAR(255) NOT NULL,
    filters LONGTEXT,
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL DEFAULT '',
    KEY idx_audience_ws (workspace_id, created_at),
    CONSTRAINT fk_audience_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS campaigns (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    name VARCHAR(255) NOT NULL,
    goal VARCHAR(80) NOT NULL DEFAULT '',
    status VARCHAR(40) NOT NULL DEFAULT 'draft',
    audience_id VARCHAR(36) NOT NULL DEFAULT '',
    audience_filters LONGTEXT,
    channels LONGTEXT,
    account_ids LONGTEXT,
    content LONGTEXT,
    scheduled_at VARCHAR(40) NOT NULL DEFAULT '',
    limits LONGTEXT,
    tracking LONGTEXT,
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL DEFAULT '',
    KEY idx_campaign_ws (workspace_id, status, created_at),
    CONSTRAINT fk_campaign_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS scheduled_posts (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    caption TEXT,
    networks TEXT,
    account_ids TEXT,
    media VARCHAR(2000) NOT NULL DEFAULT '',
    scheduled_at VARCHAR(40) NOT NULL,
    status VARCHAR(40) NOT NULL DEFAULT 'queued',
    detail TEXT,
    created_at VARCHAR(40) NOT NULL,
    KEY idx_sched (workspace_id, status, scheduled_at),
    CONSTRAINT fk_sched_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS social_publish_attempts (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    scheduled_post_id VARCHAR(36) NOT NULL,
    account_id VARCHAR(36) NOT NULL,
    platform VARCHAR(40) NOT NULL,
    provider_ref VARCHAR(255) NOT NULL DEFAULT '',
    response_id VARCHAR(255) NOT NULL DEFAULT '',
    status VARCHAR(40) NOT NULL DEFAULT 'pending',
    attempts INT NOT NULL DEFAULT 0,
    detail VARCHAR(500) NOT NULL DEFAULT '',
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL DEFAULT '',
    UNIQUE KEY uq_social_publish_account (scheduled_post_id, account_id),
    KEY idx_social_publish_retry (status, updated_at),
    CONSTRAINT fk_social_publish_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
    CONSTRAINT fk_social_publish_post FOREIGN KEY (scheduled_post_id) REFERENCES scheduled_posts(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS meta_ad_accounts (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    name VARCHAR(255) NOT NULL DEFAULT '',
    ad_account_id VARCHAR(80) NOT NULL DEFAULT '',
    access_token TEXT,
    settings LONGTEXT,
    page_id VARCHAR(80) NOT NULL DEFAULT '',
    pixel_id VARCHAR(80) NOT NULL DEFAULT '',
    default_sequence VARCHAR(255) NOT NULL DEFAULT '',
    status VARCHAR(40) NOT NULL DEFAULT 'sandbox',
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL DEFAULT '',
    CONSTRAINT fk_ads_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS ad_network_accounts (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    platform VARCHAR(40) NOT NULL,
    name VARCHAR(255) NOT NULL DEFAULT '',
    advertiser_id VARCHAR(120) NOT NULL DEFAULT '',
    credentials LONGTEXT,
    settings LONGTEXT,
    status VARCHAR(40) NOT NULL DEFAULT 'pending',
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL DEFAULT '',
    KEY idx_ad_network_ws (workspace_id, platform, created_at),
    CONSTRAINT fk_ad_network_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS ad_optimization_rules (
    id VARCHAR(36) PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    account_id VARCHAR(36) NOT NULL,
    campaign_id VARCHAR(80) NOT NULL,
    minimum_30d_spend DECIMAL(20,6) NOT NULL,
    maximum_30d_conversions DECIMAL(20,6) NOT NULL DEFAULT 0,
    conversion_limit_enabled TINYINT NOT NULL DEFAULT 1,
    enabled TINYINT NOT NULL DEFAULT 1,
    last_checked_at VARCHAR(40) NOT NULL DEFAULT '',
    last_action VARCHAR(40) NOT NULL DEFAULT '',
    last_detail VARCHAR(500) NOT NULL DEFAULT '',
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL DEFAULT '',
    UNIQUE KEY uq_ad_opt_campaign (workspace_id, account_id, campaign_id),
    KEY idx_ad_opt_due (enabled, last_checked_at),
    CONSTRAINT fk_ad_opt_ws FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);
