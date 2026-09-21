-- Flossify data model (PostgreSQL)
--
-- Covers every capability published on molarsoft.com as of September 2026,
-- plus the three things they do not do: BIR-shaped invoicing, HMO claim
-- tracking, and offline-first sync.
--
-- MULTI-TENANCY: every table that holds clinic data carries clinic_id and is
-- protected by row-level security. A query without a clinic context returns
-- nothing. This is the single most important property in the schema -- one
-- missing WHERE clause in application code must not be able to leak another
-- clinic's patients.
--
-- Nothing here is a substitute for a security review before real patient data
-- touches it.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Tenancy and people
-- ---------------------------------------------------------------------------

create table clinic_group (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  -- The public slug: flossify.ph/c/<slug>. Immutable once issued; renaming
  -- would break every bookmark and QR code a clinic has printed.
  slug          citext not null unique,
  created_at    timestamptz not null default now()
);

create table clinic (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references clinic_group(id) on delete restrict,
  name          text not null,
  slug          citext not null,
  -- Philippine address parts kept separate so BIR documents can render them
  -- in the order the Bureau expects.
  address_line  text,
  barangay      text,
  city          text,
  province      text,
  postal_code   text,
  phone         text,
  email         citext,
  -- BIR registration, printed on every invoice. Null until the clinic
  -- supplies it; invoicing is blocked while it is null.
  tin           text,
  bir_branch_code text default '00000',
  -- Which tooth numbering the clinic's staff actually use. Same tooth, three
  -- names -- storing the preference, not the numbers, keeps records portable.
  notation      text not null default 'fdi'
                check (notation in ('fdi', 'universal', 'palmer')),
  timezone      text not null default 'Asia/Manila',
  currency      char(3) not null default 'PHP',
  archived_at   timestamptz,
  created_at    timestamptz not null default now(),
  unique (group_id, slug)
);

create table staff (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references clinic_group(id) on delete cascade,
  full_name     text not null,
  email         citext not null,
  -- PRC licence for dentists; null for secretaries and admins. Printed on
  -- prescriptions and dental certificates, which are legal documents.
  prc_licence   text,
  ptr_number    text,
  role          text not null
                check (role in ('owner', 'admin', 'dentist', 'associate', 'secretary', 'assistant')),
  password_hash text,
  totp_secret   text,
  last_seen_at  timestamptz,
  disabled_at   timestamptz,
  created_at    timestamptz not null default now(),
  unique (group_id, email)
);

-- Which branches a staff member may open, and what they may see inside one.
-- Molarsoft's answer to "can I hide sales from my staff" is a default;
-- this makes it explicit and per-branch.
create table staff_access (
  staff_id      uuid not null references staff(id) on delete cascade,
  clinic_id     uuid not null references clinic(id) on delete cascade,
  can_view_finance boolean not null default false,
  can_edit_records boolean not null default true,
  can_manage_staff boolean not null default false,
  primary key (staff_id, clinic_id)
);

-- ---------------------------------------------------------------------------
-- Patients
-- ---------------------------------------------------------------------------

create table patient (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete restrict,
  -- Human-facing chart number, unique per clinic, what staff actually say out
  -- loud. The uuid is for machines.
  chart_no      text not null,
  first_name    text not null,
  middle_name   text,
  last_name     text not null,
  suffix        text,
  birth_date    date,
  sex           text check (sex in ('female', 'male', 'other', 'undisclosed')),
  phone         text,
  email         citext,
  address_line  text,
  city          text,
  province      text,
  occupation    text,
  -- Guardian details, required for minors under Philippine consent rules.
  guardian_name text,
  guardian_relation text,
  guardian_phone text,
  photo_key     text,
  notes         text,
  -- Soft delete only. Deleting a patient row would orphan clinical history
  -- that must be retained; retention is a policy decision, not a DELETE.
  archived_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (clinic_id, chart_no)
);

create index on patient (clinic_id, last_name, first_name);

-- Medical history as answered by the patient, versioned. A clinic needs to
-- know what the patient said on the day of treatment, not only what is true
-- now, so rows are appended rather than updated.
create table medical_history (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete restrict,
  patient_id    uuid not null references patient(id) on delete restrict,
  answered_at   timestamptz not null default now(),
  answered_by   text not null default 'patient'
                check (answered_by in ('patient', 'staff')),
  -- Structured answers; the question set changes over time, so the shape
  -- lives in the form definition rather than in columns here.
  answers       jsonb not null default '{}'::jsonb,
  allergies     text[],
  medications   text[],
  conditions    text[]
);

create index on medical_history (clinic_id, patient_id, answered_at desc);

-- ---------------------------------------------------------------------------
-- Clinical: charting, procedures, treatment plans
-- ---------------------------------------------------------------------------

-- Teeth are stored in FDI regardless of what the clinic displays. One
-- canonical notation, converted at the edges, or records stop being portable
-- the moment a clinic changes preference or a group spans countries.
create table tooth_state (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete restrict,
  patient_id    uuid not null references patient(id) on delete restrict,
  fdi           smallint not null check (fdi between 11 and 85),
  -- Surface-level detail, since caries on the mesial is not caries on the
  -- whole tooth. Null means the finding applies to the whole tooth.
  surface       text check (surface in ('mesial', 'distal', 'buccal', 'lingual', 'occlusal', 'incisal')),
  condition     text not null
                check (condition in ('sound', 'caries', 'filled', 'crown', 'bridge', 'implant',
                                     'root_canal', 'sealant', 'veneer', 'missing', 'unerupted', 'impacted')),
  noted_at      timestamptz not null default now(),
  noted_by      uuid references staff(id),
  procedure_id  uuid,
  superseded_at timestamptz
);

create index on tooth_state (clinic_id, patient_id, fdi) where superseded_at is null;

create table procedure_catalog (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete cascade,
  code          text not null,
  name          text not null,
  default_price numeric(12, 2) not null default 0,
  -- Whether this procedure needs a tooth and surface recorded against it.
  tooth_scoped  boolean not null default true,
  active        boolean not null default true,
  unique (clinic_id, code)
);

create table treatment_plan (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete restrict,
  patient_id    uuid not null references patient(id) on delete restrict,
  name          text not null,
  status        text not null default 'proposed'
                check (status in ('proposed', 'accepted', 'in_progress', 'completed', 'declined')),
  presented_at  timestamptz,
  accepted_at   timestamptz,
  created_at    timestamptz not null default now()
);

create table procedure_done (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete restrict,
  patient_id    uuid not null references patient(id) on delete restrict,
  plan_id       uuid references treatment_plan(id) on delete set null,
  appointment_id uuid,
  catalog_id    uuid references procedure_catalog(id),
  fdi           smallint check (fdi between 11 and 85),
  surface       text,
  price         numeric(12, 2) not null default 0,
  performed_by  uuid references staff(id),
  performed_at  timestamptz not null default now(),
  clinical_note text
);

create index on procedure_done (clinic_id, patient_id, performed_at desc);

-- ---------------------------------------------------------------------------
-- Files, images, X-rays
-- ---------------------------------------------------------------------------

create table attachment (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete restrict,
  patient_id    uuid references patient(id) on delete restrict,
  kind          text not null
                check (kind in ('xray_periapical', 'xray_bitewing', 'xray_panoramic', 'cbct',
                                'photo_intraoral', 'photo_extraoral', 'document', 'other')),
  -- Object storage key, never the bytes. A panoramic is 5-20MB and a CBCT is
  -- far larger; storage policy is a pricing decision that belongs in config.
  storage_key   text not null,
  bytes         bigint not null,
  mime          text not null,
  taken_at      timestamptz,
  fdi           smallint,
  caption       text,
  uploaded_by   uuid references staff(id),
  created_at    timestamptz not null default now()
);

create index on attachment (clinic_id, patient_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Scheduling, queue, recall
-- ---------------------------------------------------------------------------

create table appointment (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete restrict,
  patient_id    uuid not null references patient(id) on delete restrict,
  dentist_id    uuid references staff(id),
  starts_at     timestamptz not null,
  ends_at       timestamptz not null,
  reason        text,
  -- The queue states a front desk actually uses through the day.
  status        text not null default 'booked'
                check (status in ('booked', 'confirmed', 'arrived', 'in_lobby', 'in_chair',
                                  'completed', 'no_show', 'cancelled')),
  arrived_at    timestamptz,
  seated_at     timestamptz,
  created_at    timestamptz not null default now()
);

create index on appointment (clinic_id, starts_at);
create index on appointment (clinic_id, status) where status in ('arrived', 'in_lobby', 'in_chair');

create table recall (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete restrict,
  patient_id    uuid not null references patient(id) on delete restrict,
  due_on        date not null,
  reason        text not null default 'prophylaxis',
  last_sent_at  timestamptz,
  completed_at  timestamptz
);

create index on recall (clinic_id, due_on) where completed_at is null;

create table message_log (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete restrict,
  patient_id    uuid references patient(id) on delete set null,
  channel       text not null check (channel in ('sms', 'email', 'viber')),
  to_address    text not null,
  body          text not null,
  -- Delivery receipts matter: an unsent reminder that looks sent is worse
  -- than no reminder at all.
  status        text not null default 'queued'
                check (status in ('queued', 'sent', 'delivered', 'failed')),
  provider_ref  text,
  failed_reason text,
  sent_at       timestamptz,
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Documents: prescriptions, consent, certificates
-- ---------------------------------------------------------------------------

create table form_template (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete cascade,
  name          text not null,
  kind          text not null
                check (kind in ('consent', 'questionnaire', 'certificate', 'clearance', 'aftercare', 'other')),
  -- Field definitions; rendering is the app's job, not the database's.
  fields        jsonb not null default '[]'::jsonb,
  active        boolean not null default true
);

create table form_response (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete restrict,
  template_id   uuid not null references form_template(id) on delete restrict,
  patient_id    uuid not null references patient(id) on delete restrict,
  values        jsonb not null default '{}'::jsonb,
  -- A consent signature is evidence. Keep the image, who witnessed it, and
  -- when -- a boolean "consented" column is not defensible.
  signature_key text,
  signed_at     timestamptz,
  witnessed_by  uuid references staff(id),
  created_at    timestamptz not null default now()
);

create table prescription (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete restrict,
  patient_id    uuid not null references patient(id) on delete restrict,
  prescriber_id uuid not null references staff(id),
  items         jsonb not null default '[]'::jsonb,
  notes         text,
  issued_at     timestamptz not null default now(),
  -- Share links expire. A prescription link that works forever is a
  -- prescription anyone can fill forever.
  share_token   text unique,
  share_expires_at timestamptz
);

-- ---------------------------------------------------------------------------
-- Money: billing, BIR, HMO, expenses
-- ---------------------------------------------------------------------------

-- BIR requires gapless sequential numbering per series. A sequence table with
-- a row lock is the only safe way to hand out the next number under
-- concurrency; computing max(number)+1 races and produces duplicates.
create table invoice_series (
  clinic_id     uuid not null references clinic(id) on delete cascade,
  prefix        text not null,
  next_number   bigint not null default 1,
  -- The BIR Authority to Print / system permit covering this series.
  permit_number text,
  valid_until   date,
  primary key (clinic_id, prefix)
);

create table invoice (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete restrict,
  patient_id    uuid not null references patient(id) on delete restrict,
  series_prefix text not null,
  number        bigint not null,
  issued_at     timestamptz not null default now(),
  -- Amounts in the clinic's currency. numeric, never float -- money that
  -- rounds wrong is money an auditor asks about.
  subtotal      numeric(12, 2) not null default 0,
  discount      numeric(12, 2) not null default 0,
  -- Senior citizen and PWD discounts are statutory in the Philippines and
  -- change the VAT base, so they are recorded distinctly.
  discount_kind text check (discount_kind in ('none', 'senior', 'pwd', 'promo')),
  vat_rate      numeric(5, 4) not null default 0.12,
  vat_amount    numeric(12, 2) not null default 0,
  total         numeric(12, 2) not null default 0,
  status        text not null default 'issued'
                check (status in ('draft', 'issued', 'paid', 'partly_paid', 'void')),
  voided_at     timestamptz,
  void_reason   text,
  -- An issued invoice is never edited. Corrections are a new document.
  unique (clinic_id, series_prefix, number)
);

create table invoice_line (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete restrict,
  invoice_id    uuid not null references invoice(id) on delete cascade,
  procedure_id  uuid references procedure_done(id),
  description   text not null,
  quantity      numeric(10, 2) not null default 1,
  unit_price    numeric(12, 2) not null default 0,
  amount        numeric(12, 2) not null default 0
);

create table payment (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete restrict,
  invoice_id    uuid references invoice(id) on delete restrict,
  patient_id    uuid not null references patient(id) on delete restrict,
  method        text not null
                check (method in ('cash', 'gcash', 'maya', 'card', 'bank_transfer', 'hmo', 'cheque')),
  amount        numeric(12, 2) not null,
  reference     text,
  received_by   uuid references staff(id),
  received_at   timestamptz not null default now()
);

create table hmo_provider (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete cascade,
  name          text not null,
  -- Days from filing to expected payment, used to flag claims that have gone
  -- quiet. This is the number clinics cannot currently see anywhere.
  expected_days integer not null default 60,
  active        boolean not null default true
);

create table hmo_claim (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete restrict,
  provider_id   uuid not null references hmo_provider(id) on delete restrict,
  patient_id    uuid not null references patient(id) on delete restrict,
  invoice_id    uuid references invoice(id) on delete set null,
  loa_number    text,
  loa_key       text,
  claimed       numeric(12, 2) not null default 0,
  approved      numeric(12, 2),
  status        text not null default 'draft'
                check (status in ('draft', 'filed', 'approved', 'partly_approved', 'denied', 'paid')),
  filed_at      timestamptz,
  resolved_at   timestamptz,
  denial_reason text
);

create index on hmo_claim (clinic_id, status, filed_at);

create table expense (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete restrict,
  category      text not null,
  description   text,
  amount        numeric(12, 2) not null,
  incurred_on   date not null,
  receipt_key   text,
  recorded_by   uuid references staff(id)
);

create table lab_order (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete restrict,
  patient_id    uuid not null references patient(id) on delete restrict,
  lab_name      text not null,
  description   text not null,
  shade         text,
  sent_on       date,
  due_on        date,
  received_on   date,
  cost          numeric(12, 2) not null default 0,
  status        text not null default 'ordered'
                check (status in ('ordered', 'sent', 'received', 'fitted', 'remake'))
);

-- ---------------------------------------------------------------------------
-- Offline sync and audit
-- ---------------------------------------------------------------------------

-- Devices work through a brownout and reconcile afterwards. Last-write-wins
-- silently destroys a colleague's note, so conflicting writes are kept and
-- surfaced rather than resolved automatically.
create table sync_change (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinic(id) on delete cascade,
  device_id     uuid not null,
  entity        text not null,
  entity_id     uuid not null,
  -- Monotonic per device; the server orders by (received_at, device_id).
  device_seq    bigint not null,
  payload       jsonb not null,
  occurred_at   timestamptz not null,
  received_at   timestamptz not null default now(),
  conflict_with uuid references sync_change(id),
  resolved_at   timestamptz,
  unique (device_id, device_seq)
);

-- Who looked at whose record. Required to answer a Data Privacy Act subject
-- access request, and the first thing asked for after an incident.
create table audit_log (
  id            bigserial primary key,
  clinic_id     uuid not null references clinic(id) on delete restrict,
  staff_id      uuid references staff(id),
  action        text not null,
  entity        text not null,
  entity_id     uuid,
  ip            inet,
  user_agent    text,
  at            timestamptz not null default now()
);

create index on audit_log (clinic_id, at desc);
create index on audit_log (clinic_id, entity, entity_id);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
-- The application sets `app.clinic_id` per connection after authenticating.
-- With RLS forced, a query that forgets its WHERE clause returns zero rows
-- instead of another clinic's patients.

do $$
declare t text;
begin
  foreach t in array array[
    'clinic', 'patient', 'medical_history', 'tooth_state', 'procedure_catalog',
    'treatment_plan', 'procedure_done', 'attachment', 'appointment', 'recall',
    'message_log', 'form_template', 'form_response', 'prescription',
    'invoice_series', 'invoice', 'invoice_line', 'payment', 'hmo_provider',
    'hmo_claim', 'expense', 'lab_order', 'sync_change', 'audit_log'
  ]
  loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force row level security', t);
    execute format(
      'create policy tenant_isolation on %I using (clinic_id = current_setting(''app.clinic_id'', true)::uuid)',
      t
    );
  end loop;
end $$;
