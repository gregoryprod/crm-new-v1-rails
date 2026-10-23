SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: drizzle; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA drizzle;


--
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;


--
-- Name: EXTENSION btree_gist; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION btree_gist IS 'support for indexing common datatypes in GiST';


--
-- Name: client_source; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.client_source AS ENUM (
    'QUIZ',
    'MANUAL'
);


--
-- Name: consent_source; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.consent_source AS ENUM (
    'QUIZ'
);


--
-- Name: consent_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.consent_type AS ENUM (
    'PD_OFFER',
    'MARKETING'
);


--
-- Name: lead_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.lead_status AS ENUM (
    'NEW',
    'IN_PROGRESS',
    'DONE',
    'SPAM'
);


--
-- Name: outbox_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.outbox_status AS ENUM (
    'PENDING',
    'SENT',
    'FAILED'
);


--
-- Name: user_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_role AS ENUM (
    'ADMIN',
    'OWNER'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: __drizzle_migrations; Type: TABLE; Schema: drizzle; Owner: -
--

CREATE TABLE drizzle.__drizzle_migrations (
    id integer NOT NULL,
    hash text NOT NULL,
    created_at bigint
);


--
-- Name: __drizzle_migrations_id_seq; Type: SEQUENCE; Schema: drizzle; Owner: -
--

CREATE SEQUENCE drizzle.__drizzle_migrations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: __drizzle_migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: drizzle; Owner: -
--

ALTER SEQUENCE drizzle.__drizzle_migrations_id_seq OWNED BY drizzle.__drizzle_migrations.id;


--
-- Name: appointments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appointments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    doctor_id uuid NOT NULL,
    service_id uuid NOT NULL,
    client_id uuid NOT NULL,
    patient_id uuid NOT NULL,
    title text NOT NULL,
    price_cents integer,
    prepayment_percent integer NOT NULL,
    start_at timestamp with time zone NOT NULL,
    end_at timestamp with time zone NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    note text DEFAULT ''::text NOT NULL,
    cancellation_reason text,
    lead_id uuid,
    attendance text DEFAULT 'scheduled'::text NOT NULL,
    CONSTRAINT appointments_attendance CHECK ((attendance = ANY (ARRAY['scheduled'::text, 'confirmed'::text, 'arrived'::text, 'completed'::text, 'no_show'::text]))),
    CONSTRAINT appointments_prepayment CHECK (((prepayment_percent >= 0) AND (prepayment_percent <= 100))),
    CONSTRAINT appointments_price CHECK (((price_cents IS NULL) OR (price_cents >= 0))),
    CONSTRAINT appointments_range CHECK ((start_at < end_at)),
    CONSTRAINT appointments_status CHECK ((status = ANY (ARRAY['active'::text, 'cancelled'::text]))),
    CONSTRAINT appointments_version CHECK ((version > 0))
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    actor text NOT NULL,
    entity text NOT NULL,
    entity_id uuid NOT NULL,
    action text NOT NULL,
    before jsonb,
    after jsonb,
    at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: booking_operations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.booking_operations (
    id uuid NOT NULL,
    lead_id uuid NOT NULL,
    hash text NOT NULL,
    result jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: booking_receipts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.booking_receipts (
    lead_id uuid NOT NULL,
    token_hash text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    legacy_token_hash text
);


--
-- Name: calendar_intervals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.calendar_intervals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    doctor_id uuid NOT NULL,
    kind text NOT NULL,
    start_at timestamp with time zone NOT NULL,
    end_at timestamp with time zone NOT NULL,
    CONSTRAINT calendar_intervals_kind CHECK ((kind = ANY (ARRAY['shift'::text, 'break'::text]))),
    CONSTRAINT calendar_intervals_range CHECK ((start_at < end_at))
);


--
-- Name: calendar_operations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.calendar_operations (
    id uuid NOT NULL,
    actor_id uuid NOT NULL,
    hash text NOT NULL,
    result jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: calendar_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.calendar_state (
    id integer NOT NULL,
    revision integer DEFAULT 0 NOT NULL,
    CONSTRAINT calendar_revision_positive CHECK ((revision >= 0)),
    CONSTRAINT calendar_singleton CHECK ((id = 1))
);


--
-- Name: client_duplicate_candidates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.client_duplicate_candidates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    client_id uuid NOT NULL,
    candidate_client_id uuid NOT NULL,
    CONSTRAINT client_duplicate_candidates_not_self CHECK ((client_id <> candidate_client_id))
);


--
-- Name: clients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    last_name text NOT NULL,
    first_name text NOT NULL,
    phone text,
    phone_raw text NOT NULL,
    email text,
    telegram_user_id text,
    source public.client_source NOT NULL,
    possible_duplicate boolean DEFAULT false NOT NULL,
    merged_into_id uuid,
    CONSTRAINT clients_not_merged_into_self CHECK (((merged_into_id IS NULL) OR (merged_into_id <> id))),
    CONSTRAINT clients_phone_e164 CHECK ((phone ~ '^\+[1-9][0-9]{6,14}$'::text))
);


--
-- Name: consents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.consents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    client_id uuid NOT NULL,
    type public.consent_type NOT NULL,
    granted boolean NOT NULL,
    document_version text NOT NULL,
    granted_at timestamp with time zone NOT NULL,
    source public.consent_source NOT NULL,
    ip_hash text
);


--
-- Name: doctor_services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.doctor_services (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    doctor_id uuid NOT NULL,
    title text NOT NULL,
    duration_minutes integer NOT NULL,
    price_cents integer,
    prepayment_percent integer DEFAULT 0 NOT NULL,
    CONSTRAINT doctor_services_duration CHECK (((duration_minutes >= 5) AND (duration_minutes <= 480))),
    CONSTRAINT doctor_services_prepayment CHECK (((prepayment_percent >= 0) AND (prepayment_percent <= 100))),
    CONSTRAINT doctor_services_price CHECK (((price_cents IS NULL) OR (price_cents >= 0)))
);


--
-- Name: doctors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.doctors (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    name text NOT NULL,
    specialty text DEFAULT ''::text NOT NULL
);


--
-- Name: full_crm_client_work; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.full_crm_client_work (
    client_id uuid NOT NULL,
    data jsonb NOT NULL
);


--
-- Name: full_crm_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.full_crm_documents (
    key text NOT NULL,
    data jsonb NOT NULL
);


--
-- Name: full_crm_workflow; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.full_crm_workflow (
    id integer NOT NULL,
    data jsonb NOT NULL,
    CONSTRAINT full_crm_workflow_id_check CHECK ((id = 1))
);


--
-- Name: leads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leads (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    client_id uuid NOT NULL,
    patient_id uuid NOT NULL,
    status public.lead_status DEFAULT 'NEW'::public.lead_status NOT NULL,
    assigned_to uuid,
    quiz_version text,
    raw_payload jsonb NOT NULL,
    utm jsonb,
    page_url text,
    ip_hash text,
    user_agent text,
    idempotency_key text NOT NULL,
    comment text,
    version integer DEFAULT 1 NOT NULL,
    CONSTRAINT leads_version_positive CHECK ((version > 0))
);


--
-- Name: legacy_client_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.legacy_client_records (
    source_id text NOT NULL,
    source_key text NOT NULL,
    client_id uuid NOT NULL,
    payload jsonb NOT NULL,
    hash text NOT NULL,
    imported_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: legacy_imports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.legacy_imports (
    id text NOT NULL,
    hash text NOT NULL,
    manifest jsonb NOT NULL,
    archive jsonb NOT NULL,
    counts jsonb NOT NULL,
    imported_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: login_throttle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.login_throttle (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    key text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    window_started_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: outbox; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.outbox (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    type text NOT NULL,
    payload jsonb NOT NULL,
    status public.outbox_status DEFAULT 'PENDING'::public.outbox_status NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    last_error text,
    next_attempt_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT outbox_attempts_non_negative CHECK ((attempts >= 0))
);


--
-- Name: patients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.patients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    client_id uuid NOT NULL,
    species text NOT NULL,
    name text,
    breed text,
    age_text text,
    weight text,
    notes text
);


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    booking_id uuid NOT NULL,
    client_id uuid NOT NULL,
    patient_id uuid NOT NULL,
    doctor_id uuid NOT NULL,
    service_id uuid NOT NULL,
    title text NOT NULL,
    amount_cents integer NOT NULL,
    currency text DEFAULT 'RUB'::text NOT NULL,
    method text NOT NULL,
    paid_at timestamp with time zone DEFAULT now() NOT NULL,
    actor_id uuid NOT NULL,
    note text DEFAULT ''::text NOT NULL,
    CONSTRAINT payments_amount_positive CHECK ((amount_cents > 0)),
    CONSTRAINT payments_currency CHECK ((currency = 'RUB'::text)),
    CONSTRAINT payments_method CHECK ((method = ANY (ARRAY['cash'::text, 'card'::text, 'transfer'::text]))),
    CONSTRAINT payments_note_length CHECK ((length(note) <= 1000))
);


--
-- Name: rate_limits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rate_limits (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    key text NOT NULL,
    hits integer DEFAULT 0 NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    CONSTRAINT rate_limits_hits_non_negative CHECK ((hits >= 0))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid NOT NULL,
    token_hash text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    revoked_at timestamp with time zone
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    email text NOT NULL,
    name text NOT NULL,
    role public.user_role NOT NULL,
    password_hash text NOT NULL,
    telegram_user_id text,
    active boolean DEFAULT true NOT NULL,
    CONSTRAINT users_email_lowercase CHECK ((email = lower(email)))
);


--
-- Name: __drizzle_migrations id; Type: DEFAULT; Schema: drizzle; Owner: -
--

ALTER TABLE ONLY drizzle.__drizzle_migrations ALTER COLUMN id SET DEFAULT nextval('drizzle.__drizzle_migrations_id_seq'::regclass);


--
-- Name: __drizzle_migrations __drizzle_migrations_pkey; Type: CONSTRAINT; Schema: drizzle; Owner: -
--

ALTER TABLE ONLY drizzle.__drizzle_migrations
    ADD CONSTRAINT __drizzle_migrations_pkey PRIMARY KEY (id);


--
-- Name: appointments appointments_no_overlap; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_no_overlap EXCLUDE USING gist (doctor_id WITH =, tstzrange(start_at, end_at, '[)'::text) WITH &&) WHERE ((status = 'active'::text));


--
-- Name: appointments appointments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: booking_operations booking_operations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.booking_operations
    ADD CONSTRAINT booking_operations_pkey PRIMARY KEY (id);


--
-- Name: booking_receipts booking_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.booking_receipts
    ADD CONSTRAINT booking_receipts_pkey PRIMARY KEY (lead_id);


--
-- Name: calendar_intervals calendar_intervals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_intervals
    ADD CONSTRAINT calendar_intervals_pkey PRIMARY KEY (id);


--
-- Name: calendar_operations calendar_operations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_operations
    ADD CONSTRAINT calendar_operations_pkey PRIMARY KEY (id);


--
-- Name: calendar_state calendar_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_state
    ADD CONSTRAINT calendar_state_pkey PRIMARY KEY (id);


--
-- Name: client_duplicate_candidates client_duplicate_candidates_pair_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_duplicate_candidates
    ADD CONSTRAINT client_duplicate_candidates_pair_unique UNIQUE (client_id, candidate_client_id);


--
-- Name: client_duplicate_candidates client_duplicate_candidates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_duplicate_candidates
    ADD CONSTRAINT client_duplicate_candidates_pkey PRIMARY KEY (id);


--
-- Name: clients clients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id);


--
-- Name: consents consents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consents
    ADD CONSTRAINT consents_pkey PRIMARY KEY (id);


--
-- Name: doctor_services doctor_services_id_doctor_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.doctor_services
    ADD CONSTRAINT doctor_services_id_doctor_unique UNIQUE (id, doctor_id);


--
-- Name: doctor_services doctor_services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.doctor_services
    ADD CONSTRAINT doctor_services_pkey PRIMARY KEY (id);


--
-- Name: doctors doctors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.doctors
    ADD CONSTRAINT doctors_pkey PRIMARY KEY (id);


--
-- Name: full_crm_client_work full_crm_client_work_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.full_crm_client_work
    ADD CONSTRAINT full_crm_client_work_pkey PRIMARY KEY (client_id);


--
-- Name: full_crm_documents full_crm_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.full_crm_documents
    ADD CONSTRAINT full_crm_documents_pkey PRIMARY KEY (key);


--
-- Name: full_crm_workflow full_crm_workflow_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.full_crm_workflow
    ADD CONSTRAINT full_crm_workflow_pkey PRIMARY KEY (id);


--
-- Name: leads leads_patient_client_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT leads_patient_client_unique UNIQUE (id, patient_id, client_id);


--
-- Name: leads leads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT leads_pkey PRIMARY KEY (id);


--
-- Name: legacy_client_records legacy_client_records_client_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legacy_client_records
    ADD CONSTRAINT legacy_client_records_client_id_unique UNIQUE (client_id);


--
-- Name: legacy_client_records legacy_client_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legacy_client_records
    ADD CONSTRAINT legacy_client_records_pkey PRIMARY KEY (source_id);


--
-- Name: legacy_client_records legacy_client_records_source_key_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legacy_client_records
    ADD CONSTRAINT legacy_client_records_source_key_unique UNIQUE (source_key);


--
-- Name: legacy_imports legacy_imports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legacy_imports
    ADD CONSTRAINT legacy_imports_pkey PRIMARY KEY (id);


--
-- Name: login_throttle login_throttle_key_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_throttle
    ADD CONSTRAINT login_throttle_key_unique UNIQUE (key);


--
-- Name: login_throttle login_throttle_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_throttle
    ADD CONSTRAINT login_throttle_pkey PRIMARY KEY (id);


--
-- Name: outbox outbox_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox
    ADD CONSTRAINT outbox_pkey PRIMARY KEY (id);


--
-- Name: patients patients_id_client_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patients
    ADD CONSTRAINT patients_id_client_id_unique UNIQUE (id, client_id);


--
-- Name: patients patients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patients
    ADD CONSTRAINT patients_pkey PRIMARY KEY (id);


--
-- Name: payments payments_booking_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_booking_id_unique UNIQUE (booking_id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: rate_limits rate_limits_key_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_limits
    ADD CONSTRAINT rate_limits_key_unique UNIQUE (key);


--
-- Name: rate_limits rate_limits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_limits
    ADD CONSTRAINT rate_limits_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_token_hash_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_token_hash_unique UNIQUE (token_hash);


--
-- Name: users users_email_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_unique UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: appointments_active_lead_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX appointments_active_lead_unique ON public.appointments USING btree (lead_id) WHERE (status = 'active'::text);


--
-- Name: appointments_client_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX appointments_client_idx ON public.appointments USING btree (client_id);


--
-- Name: appointments_doctor_start_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX appointments_doctor_start_idx ON public.appointments USING btree (doctor_id, start_at);


--
-- Name: audit_log_entity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_entity_idx ON public.audit_log USING btree (entity, entity_id, at);


--
-- Name: calendar_intervals_doctor_start_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX calendar_intervals_doctor_start_idx ON public.calendar_intervals USING btree (doctor_id, start_at);


--
-- Name: client_duplicate_candidates_candidate_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX client_duplicate_candidates_candidate_idx ON public.client_duplicate_candidates USING btree (candidate_client_id);


--
-- Name: clients_phone_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX clients_phone_idx ON public.clients USING btree (phone);


--
-- Name: consents_client_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX consents_client_id_idx ON public.consents USING btree (client_id);


--
-- Name: doctor_services_doctor_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX doctor_services_doctor_idx ON public.doctor_services USING btree (doctor_id);


--
-- Name: leads_assigned_to_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX leads_assigned_to_idx ON public.leads USING btree (assigned_to);


--
-- Name: leads_client_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX leads_client_id_idx ON public.leads USING btree (client_id);


--
-- Name: leads_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX leads_created_at_idx ON public.leads USING btree (created_at DESC NULLS LAST);


--
-- Name: leads_idempotency_key_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX leads_idempotency_key_unique ON public.leads USING btree (idempotency_key);


--
-- Name: leads_status_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX leads_status_created_at_idx ON public.leads USING btree (status, created_at DESC NULLS LAST);


--
-- Name: login_throttle_window_started_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX login_throttle_window_started_at_idx ON public.login_throttle USING btree (window_started_at);


--
-- Name: outbox_status_next_attempt_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX outbox_status_next_attempt_at_idx ON public.outbox USING btree (status, next_attempt_at);


--
-- Name: patients_client_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX patients_client_id_idx ON public.patients USING btree (client_id);


--
-- Name: payments_client_paid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payments_client_paid_idx ON public.payments USING btree (client_id, paid_at);


--
-- Name: payments_paid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payments_paid_idx ON public.payments USING btree (paid_at);


--
-- Name: rate_limits_expires_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX rate_limits_expires_at_idx ON public.rate_limits USING btree (expires_at);


--
-- Name: sessions_expires_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sessions_expires_at_idx ON public.sessions USING btree (expires_at);


--
-- Name: sessions_user_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sessions_user_id_idx ON public.sessions USING btree (user_id);


--
-- Name: appointments appointments_client_id_clients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_client_id_clients_id_fk FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE RESTRICT;


--
-- Name: appointments appointments_doctor_id_doctors_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_doctor_id_doctors_id_fk FOREIGN KEY (doctor_id) REFERENCES public.doctors(id) ON DELETE RESTRICT;


--
-- Name: appointments appointments_lead_patient_client_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_lead_patient_client_fk FOREIGN KEY (lead_id, patient_id, client_id) REFERENCES public.leads(id, patient_id, client_id) ON DELETE RESTRICT;


--
-- Name: appointments appointments_patient_client_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_patient_client_fk FOREIGN KEY (patient_id, client_id) REFERENCES public.patients(id, client_id) ON DELETE RESTRICT;


--
-- Name: appointments appointments_service_doctor_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_service_doctor_fk FOREIGN KEY (service_id, doctor_id) REFERENCES public.doctor_services(id, doctor_id) ON DELETE RESTRICT;


--
-- Name: booking_operations booking_operations_lead_id_leads_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.booking_operations
    ADD CONSTRAINT booking_operations_lead_id_leads_id_fk FOREIGN KEY (lead_id) REFERENCES public.leads(id) ON DELETE RESTRICT;


--
-- Name: booking_receipts booking_receipts_lead_id_leads_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.booking_receipts
    ADD CONSTRAINT booking_receipts_lead_id_leads_id_fk FOREIGN KEY (lead_id) REFERENCES public.leads(id) ON DELETE RESTRICT;


--
-- Name: calendar_intervals calendar_intervals_doctor_id_doctors_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_intervals
    ADD CONSTRAINT calendar_intervals_doctor_id_doctors_id_fk FOREIGN KEY (doctor_id) REFERENCES public.doctors(id) ON DELETE RESTRICT;


--
-- Name: calendar_operations calendar_operations_actor_id_users_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_operations
    ADD CONSTRAINT calendar_operations_actor_id_users_id_fk FOREIGN KEY (actor_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: client_duplicate_candidates client_duplicate_candidates_candidate_client_id_clients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_duplicate_candidates
    ADD CONSTRAINT client_duplicate_candidates_candidate_client_id_clients_id_fk FOREIGN KEY (candidate_client_id) REFERENCES public.clients(id) ON DELETE CASCADE;


--
-- Name: client_duplicate_candidates client_duplicate_candidates_client_id_clients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_duplicate_candidates
    ADD CONSTRAINT client_duplicate_candidates_client_id_clients_id_fk FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;


--
-- Name: clients clients_merged_into_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_merged_into_id_fk FOREIGN KEY (merged_into_id) REFERENCES public.clients(id) ON DELETE SET NULL;


--
-- Name: consents consents_client_id_clients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consents
    ADD CONSTRAINT consents_client_id_clients_id_fk FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE RESTRICT;


--
-- Name: doctor_services doctor_services_doctor_id_doctors_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.doctor_services
    ADD CONSTRAINT doctor_services_doctor_id_doctors_id_fk FOREIGN KEY (doctor_id) REFERENCES public.doctors(id) ON DELETE RESTRICT;


--
-- Name: full_crm_client_work full_crm_client_work_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.full_crm_client_work
    ADD CONSTRAINT full_crm_client_work_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE RESTRICT;


--
-- Name: leads leads_assigned_to_users_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT leads_assigned_to_users_id_fk FOREIGN KEY (assigned_to) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: leads leads_client_id_clients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT leads_client_id_clients_id_fk FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE RESTRICT;


--
-- Name: leads leads_patient_belongs_to_client_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT leads_patient_belongs_to_client_fk FOREIGN KEY (patient_id, client_id) REFERENCES public.patients(id, client_id) ON DELETE RESTRICT;


--
-- Name: legacy_client_records legacy_client_records_client_id_clients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legacy_client_records
    ADD CONSTRAINT legacy_client_records_client_id_clients_id_fk FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE RESTRICT;


--
-- Name: patients patients_client_id_clients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patients
    ADD CONSTRAINT patients_client_id_clients_id_fk FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE RESTRICT;


--
-- Name: payments payments_actor_id_users_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_actor_id_users_id_fk FOREIGN KEY (actor_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: payments payments_booking_id_appointments_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_booking_id_appointments_id_fk FOREIGN KEY (booking_id) REFERENCES public.appointments(id) ON DELETE RESTRICT;


--
-- Name: payments payments_client_id_clients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_client_id_clients_id_fk FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE RESTRICT;


--
-- Name: payments payments_doctor_id_doctors_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_doctor_id_doctors_id_fk FOREIGN KEY (doctor_id) REFERENCES public.doctors(id) ON DELETE RESTRICT;


--
-- Name: payments payments_patient_id_patients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_patient_id_patients_id_fk FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE RESTRICT;


--
-- Name: payments payments_service_id_doctor_services_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_service_id_doctor_services_id_fk FOREIGN KEY (service_id) REFERENCES public.doctor_services(id) ON DELETE RESTRICT;


--
-- Name: sessions sessions_user_id_users_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_user_id_users_id_fk FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261019000000');

