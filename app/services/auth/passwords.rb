module Auth
  # Argon2id. New hashes use m=32 MiB, t=2, p=1 (above the OWASP minimum of 19 MiB, t=2);
  # hashes written by the previous Node app (m=19456) verify unchanged.
  module Passwords
    module_function

    def hash(password)
      Argon2::Password.new(t_cost: 2, m_cost: 15, p_cost: 1).create(password)
    end

    def verify(password_hash, password)
      Argon2::Password.verify_password(password, password_hash)
    rescue Argon2::ArgonHashFail, Argon2::Errors::InvalidHash, ArgumentError
      false
    end

    # Burns comparable CPU when the account does not exist, so timing does not reveal emails.
    def verify_against_dummy(password)
      @dummy ||= hash("dummy-password-for-timing-equalisation")
      verify(@dummy, password)
    end
  end
end
