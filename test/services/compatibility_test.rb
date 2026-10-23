require "test_helper"

# Values computed with the previous Node implementation: identities, tokens and keyed hashes
# must stay byte-identical so the same database works for either application.
class CompatibilityTest < ActiveSupport::TestCase
  test "legacy ids match the Node legacyId()" do
    assert_equal "26e36183-8908-52e5-94d0-9f6aaa2f36f9", CryptoHelpers.legacy_id("doctor", "42")
    assert_equal "ff8a3a46-b88a-56cf-a146-1cbf738057d9", CryptoHelpers.legacy_id("yclients-shift", "7:2026-10-01:09:00-18:00")
  end

  test "keyed hash and booking receipt match Node crypto" do
    assert_equal "R6_9yKdKi9eeLrmTcvfXoujv41A8-AeqzwAGoFwKb84", CryptoHelpers.keyed_hash("secret", "session", "tok")
    assert_equal "1d5bdea8c812a4878c45dc3d03ebb9a274d535e4906fdfab9d3b63e218bdf33b",
                 Booking::Receipt.token_for("00000000-0000-4000-8000-000000000001")
  end

  test "argon2 hashes written by the Node app verify" do
    node_hash = "$argon2id$v=19$m=19456,t=2,p=1$nZGKhO9ePmoPae87V2zNMQ$YF1MwnyGXApJnncof+6hqtaGrSgrQxDmxc6usqNMm9I"
    assert Auth::Passwords.verify(node_hash, "Пароль-для-проверки-1")
    assert_not Auth::Passwords.verify(node_hash, "wrong")
    assert_not Auth::Passwords.verify("not-a-hash", "x")
  end

  test "JSON timestamps use JavaScript Date#toJSON form" do
    assert_equal "2026-10-19T07:05:03.123Z", Json.iso(Time.utc(2026, 10, 19, 7, 5, 3.123456r))
    assert_equal '{"a":1,"b":0.5}', Json.dump({ "a" => 1.0, "b" => 0.5 })
  end
end
