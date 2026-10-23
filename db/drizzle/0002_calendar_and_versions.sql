CREATE TABLE "appointments" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"doctor_id" uuid NOT NULL,
	"service_id" uuid NOT NULL,
	"client_id" uuid NOT NULL,
	"patient_id" uuid NOT NULL,
	"title" text NOT NULL,
	"price_cents" integer,
	"prepayment_percent" integer NOT NULL,
	"start_at" timestamp with time zone NOT NULL,
	"end_at" timestamp with time zone NOT NULL,
	"status" text DEFAULT 'active' NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"note" text DEFAULT '' NOT NULL,
	"cancellation_reason" text,
	CONSTRAINT "appointments_range" CHECK ("appointments"."start_at" < "appointments"."end_at"),
	CONSTRAINT "appointments_status" CHECK ("appointments"."status" IN ('active', 'cancelled')),
	CONSTRAINT "appointments_version" CHECK ("appointments"."version" > 0),
	CONSTRAINT "appointments_price" CHECK ("appointments"."price_cents" IS NULL OR "appointments"."price_cents" >= 0),
	CONSTRAINT "appointments_prepayment" CHECK ("appointments"."prepayment_percent" BETWEEN 0 AND 100)
);
--> statement-breakpoint
CREATE TABLE "calendar_intervals" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"doctor_id" uuid NOT NULL,
	"kind" text NOT NULL,
	"start_at" timestamp with time zone NOT NULL,
	"end_at" timestamp with time zone NOT NULL,
	CONSTRAINT "calendar_intervals_kind" CHECK ("calendar_intervals"."kind" IN ('shift', 'break')),
	CONSTRAINT "calendar_intervals_range" CHECK ("calendar_intervals"."start_at" < "calendar_intervals"."end_at")
);
--> statement-breakpoint
CREATE TABLE "calendar_operations" (
	"id" uuid PRIMARY KEY NOT NULL,
	"actor_id" uuid NOT NULL,
	"hash" text NOT NULL,
	"result" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "calendar_state" (
	"id" integer PRIMARY KEY NOT NULL,
	"revision" integer DEFAULT 0 NOT NULL,
	CONSTRAINT "calendar_singleton" CHECK ("calendar_state"."id" = 1),
	CONSTRAINT "calendar_revision_positive" CHECK ("calendar_state"."revision" >= 0)
);
--> statement-breakpoint
CREATE TABLE "doctor_services" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"doctor_id" uuid NOT NULL,
	"title" text NOT NULL,
	"duration_minutes" integer NOT NULL,
	"price_cents" integer,
	"prepayment_percent" integer DEFAULT 0 NOT NULL,
	CONSTRAINT "doctor_services_id_doctor_unique" UNIQUE("id","doctor_id"),
	CONSTRAINT "doctor_services_duration" CHECK ("doctor_services"."duration_minutes" BETWEEN 5 AND 480),
	CONSTRAINT "doctor_services_price" CHECK ("doctor_services"."price_cents" IS NULL OR "doctor_services"."price_cents" >= 0),
	CONSTRAINT "doctor_services_prepayment" CHECK ("doctor_services"."prepayment_percent" BETWEEN 0 AND 100)
);
--> statement-breakpoint
CREATE TABLE "doctors" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"name" text NOT NULL,
	"specialty" text DEFAULT '' NOT NULL
);
--> statement-breakpoint
ALTER TABLE "leads" ADD COLUMN "version" integer DEFAULT 1 NOT NULL;--> statement-breakpoint
ALTER TABLE "appointments" ADD CONSTRAINT "appointments_doctor_id_doctors_id_fk" FOREIGN KEY ("doctor_id") REFERENCES "public"."doctors"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "appointments" ADD CONSTRAINT "appointments_client_id_clients_id_fk" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "appointments" ADD CONSTRAINT "appointments_service_doctor_fk" FOREIGN KEY ("service_id","doctor_id") REFERENCES "public"."doctor_services"("id","doctor_id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "appointments" ADD CONSTRAINT "appointments_patient_client_fk" FOREIGN KEY ("patient_id","client_id") REFERENCES "public"."patients"("id","client_id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "calendar_intervals" ADD CONSTRAINT "calendar_intervals_doctor_id_doctors_id_fk" FOREIGN KEY ("doctor_id") REFERENCES "public"."doctors"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "calendar_operations" ADD CONSTRAINT "calendar_operations_actor_id_users_id_fk" FOREIGN KEY ("actor_id") REFERENCES "public"."users"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "doctor_services" ADD CONSTRAINT "doctor_services_doctor_id_doctors_id_fk" FOREIGN KEY ("doctor_id") REFERENCES "public"."doctors"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "appointments_doctor_start_idx" ON "appointments" USING btree ("doctor_id","start_at");--> statement-breakpoint
CREATE INDEX "appointments_client_idx" ON "appointments" USING btree ("client_id");--> statement-breakpoint
CREATE INDEX "calendar_intervals_doctor_start_idx" ON "calendar_intervals" USING btree ("doctor_id","start_at");--> statement-breakpoint
CREATE INDEX "doctor_services_doctor_idx" ON "doctor_services" USING btree ("doctor_id");--> statement-breakpoint
ALTER TABLE "leads" ADD CONSTRAINT "leads_version_positive" CHECK ("leads"."version" > 0);--> statement-breakpoint
CREATE EXTENSION IF NOT EXISTS btree_gist;
--> statement-breakpoint
-- Final DB guard even if a future writer bypasses the calendar service.
ALTER TABLE appointments ADD CONSTRAINT appointments_no_overlap
EXCLUDE USING gist (doctor_id WITH =, tstzrange(start_at, end_at, '[)') WITH &&)
WHERE (status = 'active');
