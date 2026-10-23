class User < ApplicationRecord
  ROLES = %w[ADMIN OWNER].freeze

  has_many :staff_sessions, dependent: :delete_all

  # Fields that may leave the server (never the password hash).
  def public_attributes
    { id:, email:, name:, role:, active:, createdAt: created_at }
  end

  # OWNER inherits every ADMIN permission.
  def has_role?(required)
    required == "ADMIN" ? %w[ADMIN OWNER].include?(role) : role == required
  end
end
