require "test_helper"
require "webrick"

class NotificationsTest < ActiveSupport::TestCase
  FakeChannel = Struct.new(:results, :sent) do
    def name = "fake"
    def send_message(text)
      sent << text
      results.shift || Notifications::TelegramChannel::Result.success
    end
  end

  def create_lead
    payload = Leads::Payload.parse(lead_body).lead
    Leads::Intake.submit(payload, ip: nil, user_agent: nil).lead_id
  end

  def dispatch(channel) = Notifications::Dispatcher.dispatch_due(channel:, app_origin: "https://crm.example.test")

  test "sends the lead card text and marks SENT" do
    lead_id = create_lead
    channel = FakeChannel.new([], [])
    summary = dispatch(channel)
    assert_equal 1, summary.sent
    assert_includes channel.sent.first, "Новая заявка\nИванова Мария\nТелефон: +79991234567\nПитомец: кошка\nИсточник: квиз, utm_source: vk"
    assert_includes channel.sent.first, "https://crm.example.test/crm/leads/#{lead_id}"
    assert_equal "SENT", OutboxEvent.last.status
  end

  test "retries after 1/5/15 minutes, honours retry_after and fails after four attempts" do
    create_lead
    failure = Notifications::TelegramChannel::Result.failure("Telegram HTTP 429", retry_after_seconds: 120)
    channel = FakeChannel.new([ failure ], [])
    assert_equal 1, dispatch(channel).retried
    event = OutboxEvent.last
    assert_in_delta 120, event.next_attempt_at - Time.current, 5
    3.times do
      OutboxEvent.update_all("next_attempt_at = now()")
      dispatch(FakeChannel.new([ Notifications::TelegramChannel::Result.failure("down") ], []))
    end
    assert_equal "FAILED", event.reload.status
    assert_equal 4, event.attempts
    view = Notifications::DeliveryView.describe(Outbox.lead_delivery(Lead.last.id), false)
    assert_equal "failed", view.tone
  end

  test "lease fencing: a late worker cannot finish an event it no longer owns" do
    create_lead
    claimed = Outbox.claim_next(%w[lead.created])
    OutboxEvent.update_all("next_attempt_at = now()")
    again = Outbox.claim_next(%w[lead.created])
    assert_equal claimed.id, again.id
    assert_not Outbox.mark_sent(claimed)
    assert Outbox.mark_sent(again)
  end

  test "Telegram channel posts JSON and never leaks the token" do
    token = "123456:#{'A' * 35}"
    requests = []
    server = WEBrick::HTTPServer.new(Port: 0, BindAddress: "127.0.0.1", Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
    server.mount_proc("/") do |req, res|
      requests << [ req.path, JSON.parse(req.body) ]
      res.status = requests.length == 1 ? 200 : 400
      res.body = requests.length == 1 ? '{"ok":true}' : %({"ok":false,"description":"bad #{token}"})
    end
    thread = Thread.new { server.start }
    channel = Notifications::TelegramChannel.new(bot_token: token, chat_id: "-100", api_base_url: "http://127.0.0.1:#{server.config[:Port]}", timeout_seconds: 2)
    assert channel.send_message("hi").ok
    failed = channel.send_message("hi")
    assert_not failed.ok
    assert_equal "Telegram HTTP 400: bad [скрыто]", failed.error
    assert_equal "/bot#{token}/sendMessage", requests.first[0]
    assert_equal({ "chat_id" => "-100", "text" => "hi", "link_preview_options" => { "is_disabled" => true } }, requests.first[1])
  ensure
    server&.shutdown
    thread&.join
  end
end
