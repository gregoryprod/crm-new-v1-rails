# Singleton rows the application expects (the Node migrations inserted them as data; a schema
# load from db/structure.sql does not carry data). Idempotent: safe on every deploy.
ActiveRecord::Base.connection.execute(<<~SQL)
  INSERT INTO full_crm_workflow (id, data)
  VALUES (1, '{"schemaVersion":1,"revision":0,"assignments":[],"events":[],"operations":[],"updatedAt":null}')
  ON CONFLICT (id) DO NOTHING
SQL
ActiveRecord::Base.connection.execute("INSERT INTO calendar_state (id, revision) VALUES (1, 0) ON CONFLICT (id) DO NOTHING")
