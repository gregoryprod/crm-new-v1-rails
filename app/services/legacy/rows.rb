module Legacy
  # Canonical client row plus immutable source card; shared by every importer of legacy cards.
  module Rows
    module_function

    def client_rows(card)
      client_id = CryptoHelpers.legacy_id("client", card["sourceId"].to_s)
      {
        client: {
          "id" => client_id, "last_name" => card["name"], "first_name" => "", "phone" => Phone.normalize(card["phone"]),
          "phone_raw" => card["phone"], "source" => "MANUAL", "email" => card["email"].is_a?(String) ? card["email"] : nil
        },
        record: {
          "source_id" => card["sourceId"].to_s, "source_key" => card["key"], "client_id" => client_id,
          "payload" => card, "hash" => Digest::SHA256.hexdigest(JSON.generate(card))
        }
      }
    end
  end
end
