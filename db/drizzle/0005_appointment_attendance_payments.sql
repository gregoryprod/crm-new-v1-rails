CREATE TABLE "payments" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"booking_id" uuid NOT NULL,
	"client_id" uuid NOT NULL,
	"patient_id" uuid NOT NULL,
	"doctor_id" uuid NOT NULL,
	"service_id" uuid NOT NULL,
	"title" text NOT NULL,
	"amount_cents" integer NOT NULL,
	"currency" text DEFAULT 'RUB' NOT NULL,
	"method" text NOT NULL,
	"paid_at" timestamp with time zone DEFAULT now() NOT NULL,
	"actor_id" uuid NOT NULL,
	"note" text DEFAULT '' NOT NULL,
	CONSTRAINT "payments_booking_id_unique" UNIQUE("booking_id"),
	CONSTRAINT "payments_amount_positive" CHECK ("payments"."amount_cents" > 0),
	CONSTRAINT "payments_currency" CHECK ("payments"."currency" = 'RUB'),
	CONSTRAINT "payments_method" CHECK ("payments"."method" IN ('cash', 'card', 'transfer')),
	CONSTRAINT "payments_note_length" CHECK (length("payments"."note") <= 1000)
);
--> statement-breakpoint
ALTER TABLE "appointments" ADD COLUMN "attendance" text DEFAULT 'scheduled' NOT NULL;--> statement-breakpoint
ALTER TABLE "payments" ADD CONSTRAINT "payments_booking_id_appointments_id_fk" FOREIGN KEY ("booking_id") REFERENCES "public"."appointments"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "payments" ADD CONSTRAINT "payments_client_id_clients_id_fk" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "payments" ADD CONSTRAINT "payments_patient_id_patients_id_fk" FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "payments" ADD CONSTRAINT "payments_doctor_id_doctors_id_fk" FOREIGN KEY ("doctor_id") REFERENCES "public"."doctors"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "payments" ADD CONSTRAINT "payments_service_id_doctor_services_id_fk" FOREIGN KEY ("service_id") REFERENCES "public"."doctor_services"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "payments" ADD CONSTRAINT "payments_actor_id_users_id_fk" FOREIGN KEY ("actor_id") REFERENCES "public"."users"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "payments_client_paid_idx" ON "payments" USING btree ("client_id","paid_at");--> statement-breakpoint
CREATE INDEX "payments_paid_idx" ON "payments" USING btree ("paid_at");--> statement-breakpoint
ALTER TABLE "appointments" ADD CONSTRAINT "appointments_attendance" CHECK ("appointments"."attendance" IN ('scheduled', 'confirmed', 'arrived', 'completed', 'no_show'));