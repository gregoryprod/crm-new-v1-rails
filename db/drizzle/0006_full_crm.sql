CREATE TABLE full_crm_documents (key text PRIMARY KEY, data jsonb NOT NULL);
--> statement-breakpoint
CREATE TABLE full_crm_client_work (client_id uuid PRIMARY KEY REFERENCES clients(id) ON DELETE RESTRICT, data jsonb NOT NULL);
--> statement-breakpoint
CREATE TABLE full_crm_workflow (id integer PRIMARY KEY CHECK (id = 1), data jsonb NOT NULL);
--> statement-breakpoint
INSERT INTO full_crm_workflow (id,data) VALUES (1,'{"schemaVersion":1,"revision":0,"assignments":[],"events":[],"operations":[],"updatedAt":null}');
