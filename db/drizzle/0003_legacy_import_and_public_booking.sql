CREATE TABLE "booking_operations" (
	"id" uuid PRIMARY KEY NOT NULL,
	"lead_id" uuid NOT NULL,
	"hash" text NOT NULL,
	"result" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "booking_receipts" (
	"lead_id" uuid PRIMARY KEY NOT NULL,
	"token_hash" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "legacy_client_records" (
	"source_id" text PRIMARY KEY NOT NULL,
	"source_key" text NOT NULL,
	"client_id" uuid NOT NULL,
	"payload" jsonb NOT NULL,
	"hash" text NOT NULL,
	"imported_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "legacy_client_records_source_key_unique" UNIQUE("source_key"),
	CONSTRAINT "legacy_client_records_client_id_unique" UNIQUE("client_id")
);
--> statement-breakpoint
CREATE TABLE "legacy_imports" (
	"id" text PRIMARY KEY NOT NULL,
	"hash" text NOT NULL,
	"manifest" jsonb NOT NULL,
	"archive" jsonb NOT NULL,
	"counts" jsonb NOT NULL,
	"imported_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "clients" ALTER COLUMN "phone" DROP NOT NULL;--> statement-breakpoint
ALTER TABLE "appointments" ADD COLUMN "lead_id" uuid;--> statement-breakpoint
ALTER TABLE "booking_operations" ADD CONSTRAINT "booking_operations_lead_id_leads_id_fk" FOREIGN KEY ("lead_id") REFERENCES "public"."leads"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "booking_receipts" ADD CONSTRAINT "booking_receipts_lead_id_leads_id_fk" FOREIGN KEY ("lead_id") REFERENCES "public"."leads"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "legacy_client_records" ADD CONSTRAINT "legacy_client_records_client_id_clients_id_fk" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "leads" ADD CONSTRAINT "leads_patient_client_unique" UNIQUE("id","patient_id","client_id");
--> statement-breakpoint
ALTER TABLE "appointments" ADD CONSTRAINT "appointments_lead_patient_client_fk" FOREIGN KEY ("lead_id","patient_id","client_id") REFERENCES "public"."leads"("id","patient_id","client_id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "appointments_active_lead_unique" ON "appointments" USING btree ("lead_id") WHERE "appointments"."status" = 'active';--> statement-breakpoint
