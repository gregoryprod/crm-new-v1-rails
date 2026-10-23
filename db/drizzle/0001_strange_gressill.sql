CREATE TABLE "client_duplicate_candidates" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"client_id" uuid NOT NULL,
	"candidate_client_id" uuid NOT NULL,
	CONSTRAINT "client_duplicate_candidates_pair_unique" UNIQUE("client_id","candidate_client_id"),
	CONSTRAINT "client_duplicate_candidates_not_self" CHECK ("client_duplicate_candidates"."client_id" <> "client_duplicate_candidates"."candidate_client_id")
);
--> statement-breakpoint
CREATE TABLE "rate_limits" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"key" text NOT NULL,
	"hits" integer DEFAULT 0 NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	CONSTRAINT "rate_limits_key_unique" UNIQUE("key"),
	CONSTRAINT "rate_limits_hits_non_negative" CHECK ("rate_limits"."hits" >= 0)
);
--> statement-breakpoint
ALTER TABLE "client_duplicate_candidates" ADD CONSTRAINT "client_duplicate_candidates_client_id_clients_id_fk" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "client_duplicate_candidates" ADD CONSTRAINT "client_duplicate_candidates_candidate_client_id_clients_id_fk" FOREIGN KEY ("candidate_client_id") REFERENCES "public"."clients"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "client_duplicate_candidates_candidate_idx" ON "client_duplicate_candidates" USING btree ("candidate_client_id");--> statement-breakpoint
CREATE INDEX "rate_limits_expires_at_idx" ON "rate_limits" USING btree ("expires_at");--> statement-breakpoint
CREATE INDEX "leads_created_at_idx" ON "leads" USING btree ("created_at" DESC NULLS LAST);