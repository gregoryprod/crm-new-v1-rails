require "test_helper"

class YclientsImportTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir("yclients-synthetic")
    raw = File.join(@dir, "raw")
    FileUtils.mkdir_p(raw)
    day = tomorrow
    records = [
      { id: 1, staff_id: 7, staff: { name: "Врач Семь" }, services: [ { id: 30, title: "Осмотр", cost: 1500 } ],
        client: { id: 501, name: "Клиент", phone: "+79990001111", custom_fields: { "klichka-pitomtsa" => "Бобик" } },
        datetime: "#{day}T10:00:00+03:00", date: "#{day} 10:00:00", create_date: "2026-10-01 12:00:00",
        last_change_date: "2026-10-01 12:00:00", seance_length: 1800, attendance: 2, deleted: false, comment: "" },
      { id: 2, staff_id: 7, services: [], client: [], datetime: "#{day}T13:00:00+03:00", seance_length: 3600,
        attendance: 0, deleted: false, last_change_date: "x" },
      { id: 3, staff_id: 7, services: [], client: { name: "Без карты" }, datetime: "#{day}T15:00:00+03:00",
        seance_length: 1800, attendance: 0, last_change_date: "x" }
    ]
    File.write(File.join(raw, "records.json"), JSON.generate(records))
    File.write(File.join(raw, "clients.json"), JSON.generate([ { id: 501, display_name: "Синтетический Клиент", phone: "+79990001111", paid: 1500, visits: 1 } ]))
    File.write(File.join(raw, "staff_schedule.json"), JSON.generate([ { staff_id: 7, date: day, slots: [ { from: "09:00", to: "18:00" } ] } ]))
    Doctor.create!(id: CryptoHelpers.legacy_id("doctor", "7"), name: "Врач Семь")
  end

  teardown { FileUtils.remove_entry(@dir) }

  test "dry run writes nothing; apply is insert-only and re-runs change nothing" do
    source = Yclients::Source.read([ @dir ])
    counts = Yclients::CalendarImport.dry_run(source)
    assert_equal 1, counts["appointments"]["new"]
    assert_equal 1, counts["breaks"]["new"]
    assert_equal 1, counts["shifts"]["new"]
    assert_equal({ "client_without_yclients_card" => [ 3 ] }, counts["skippedRecordIds"])
    assert_equal 0, Appointment.count

    result = Yclients::CalendarImport.apply(source)
    appointment = Appointment.find(CryptoHelpers.legacy_id("yclients-record", "1"))
    assert_equal "confirmed", appointment.attendance
    assert_equal 150_000, appointment.price_cents
    assert_equal "Бобик", Patient.find(appointment.patient_id).name
    card = LegacyClientRecord.find_by(source_key: "yclients:501")
    assert_equal Yclients::CardFormat::VERSION, card.payload["cardFormat"]
    assert_equal "Синтетический Клиент", Client.find(card.client_id).last_name
    assert_equal 1, result["revision"] - 0

    again = Yclients::CalendarImport.apply(Yclients::Source.read([ @dir ]))
    assert_equal 1, again["counts"]["appointments"]["existing"]
    assert_equal 0, again["counts"]["appointments"]["new"]
    assert_equal 1, Appointment.count

    assert_equal 0, Yclients::NormalizeCards.dry_run["toChange"]
    built = FullCrm::Projections.dry_run
    assert_equal 0, built["unnormalizedYclientsCards"]
  end

  test "source errors name the file, never its content" do
    File.write(File.join(@dir, "raw", "records.json"), "{secret")
    error = assert_raises(Yclients::SourceError) { Yclients::Source.read([ @dir ]) }
    assert_equal "Invalid JSON in records.json of export 1", error.message
  end
end
