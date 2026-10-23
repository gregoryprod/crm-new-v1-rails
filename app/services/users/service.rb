module Users
  module Service
    module_function

    # Creates the OWNER from explicitly provided parameters. Never overwrites an existing
    # account (including its password); there is no public registration.
    def seed_owner(input)
      return nil if User.exists?(email: input.email)
      password_hash = Auth::Passwords.hash(input.password)
      ActiveRecord::Base.transaction do
        id = ActiveRecord::Base.connection.select_value(ApplicationRecord.sql(<<~SQL, input.email, input.name, password_hash))
          INSERT INTO users (email, name, role, password_hash) VALUES (?, ?, 'OWNER', ?)
          ON CONFLICT (email) DO NOTHING RETURNING id
        SQL
        next nil unless id
        user = User.find(id)
        AuditLog.write!(actor: "system", entity: "user", entity_id: user.id, action: "user.seeded",
                        after: { email: user.email, role: user.role, active: user.active })
        user
      end
    end

    # Deactivation revokes every open session of the user in the same transaction. The
    # current state is read under a row lock; setting the same value is a no-op.
    def set_active(actor, user_id, active)
      ActiveRecord::Base.transaction do
        current = User.lock.find_by(id: user_id)
        next nil unless current
        next current if current.active == active
        before = current.active
        current.update!(active:)
        StaffSession.where(user_id:, revoked_at: nil).update_all("revoked_at = now()") unless active
        AuditLog.write!(actor:, entity: "user", entity_id: user_id,
                        action: active ? "user.activated" : "user.deactivated",
                        before: { active: before }, after: { active: current.active })
        current
      end
    end
  end
end
