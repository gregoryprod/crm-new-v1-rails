require "test_helper"

class LeadPayloadTest < ActiveSupport::TestCase
  test "valid payload is cleaned and normalized" do
    result = Leads::Payload.parse(lead_body("last_name" => "  Иванова   Мария ", "species" => " кот "))
    assert result.ok
    assert_equal "Иванова Мария", result.lead.last_name
    assert_equal "+79991234567", result.lead.phone
    assert_equal "кот", result.lead.species
    assert_equal({ "source" => "vk", "campaign" => "autumn" }, result.lead.utm)
    assert_equal "https://quiz.example.test/form", result.lead.page_url
    assert_not result.lead.honeypot
  end

  test "errors name fields only, sorted" do
    result = Leads::Payload.parse(lead_body("phone" => "12", "consent_pd" => false, "first_name" => "123", "extra" => "x"))
    assert_not result.ok
    assert_equal %w[consent_pd first_name phone], result.fields
    assert_equal [], Leads::Payload.parse([ 1 ]).fields
  end

  test "personal data never stays in utm or the page path" do
    utm = Leads::Payload.sanitize_utm({ "source" => "ivan@example.com", "medium" => "+7 999 123 45 67", "campaign" => "123456789012", "term" => 5 })
    assert_equal({ "campaign" => "123456789012" }, utm)
    assert_equal "https://quiz.example.test/", Leads::Payload.sanitize_page_url("https://quiz.example.test/client/89991234567")
    assert_nil Leads::Payload.sanitize_page_url("javascript:alert(1)")
  end

  test "honeypot rules" do
    assert_not Leads::Payload.honeypot_filled?(nil)
    assert_not Leads::Payload.honeypot_filled?("  ")
    assert Leads::Payload.honeypot_filled?("http://spam")
    assert Leads::Payload.honeypot_filled?(0)
  end

  test "rate limit subject groups IPv6 by /64" do
    assert_equal "203.0.113.5", Leads::Throttle.rate_limit_subject("203.0.113.5")
    assert_equal "203.0.113.5", Leads::Throttle.rate_limit_subject("::ffff:203.0.113.5")
    assert_equal "2001:db8:0:1::/64", Leads::Throttle.rate_limit_subject("2001:db8:0:1:aaaa::1")
    assert_equal "2001:db8:0:0::/64", Leads::Throttle.rate_limit_subject("2001:db8::1")
    assert_nil Leads::Throttle.valid_ip("not-an-ip")
    assert_equal "2001:db8::1%eth0", Leads::Throttle.valid_ip(" 2001:db8::1%eth0 ")
  end

  test "phone normalization" do
    assert_equal "+79991234567", Phone.normalize("8 999 123-45-67")
    assert_nil Phone.normalize("12345")
    assert_nil Phone.normalize("+7 999 123 45 67 ext")
    assert_equal "+7 999 123-45-67", Phone.format("+79991234567")
  end
end
