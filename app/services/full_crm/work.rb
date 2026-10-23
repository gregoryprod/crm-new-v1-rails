module FullCrm
  # Per-client work record of the workspace: owner, tasks, comments and their events.
  module Work
    V4_UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

    module_function

    def valid_day?(value)
      value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.strptime(value, "%Y-%m-%d").iso8601 == value
    rescue Date::Error
      false
    end

    def fields!(value, keys)
      raise WorkError.new(400, "Некорректные поля запроса") unless value.is_a?(Hash) && value.keys.sort == keys.sort
    end

    def string!(value, max, required = false)
      raise WorkError.new(400, "Проверь заполнение и длину текста") if !value.is_a?(String) || value.length > max || (required && value.strip.empty?)
      value.strip
    end

    def nullable!(value, max)
      value.nil? ? nil : string!(value, max).presence
    end

    def empty(source_id)
      { "sourceId" => source_id, "revision" => 0, "owner" => nil, "tasks" => [], "comments" => [], "events" => [],
        "operations" => [], "updatedAt" => nil }
    end

    def now_iso
      Json.iso(Time.current)
    end

    def mutate!(record, body)
      p = body["payload"]
      at = now_iso
      find = lambda do |list, label, missing|
        raise WorkError.new(400, label) unless p["id"].is_a?(String) && V4_UUID.match?(p["id"])
        record[list].find { |item| item["id"] == p["id"] } || raise(WorkError.new(404, missing))
      end
      task = -> { find.("tasks", "Некорректная задача", "Задача не найдена в этой карточке") }
      comment = -> { find.("comments", "Некорректный комментарий", "Комментарий не найден в этой карточке") }
      task_values = lambda do
        title = string!(p["title"], 300, true)
        description = string!(p["description"], 4000)
        assignee = nullable!(p["assignee"], 120)
        raise WorkError.new(400, "Проверь дату срока") if !p["dueDay"].nil? && !valid_day?(p["dueDay"])
        { "title" => title, "description" => description, "assignee" => assignee, "dueDay" => p["dueDay"] }
      end
      event = case body["operation"]
      when "set_owner"
        fields!(p, %w[owner])
        owner = nullable!(p["owner"], 120)
        record["owner"] = owner
        { "type" => "owner", "text" => owner ? "Ответственный: #{owner}" : "Ответственный снят" }
      when "create_task"
        fields!(p, %w[title description dueDay assignee])
        t = { "id" => SecureRandom.uuid, **task_values.(), "status" => "open", "createdAt" => at, "updatedAt" => at,
              "completedAt" => nil, "archivedAt" => nil }
        record["tasks"] << t
        { "type" => "task", "text" => "Добавлена задача: #{t['title']}", "itemId" => t["id"] }
      when "update_task"
        fields!(p, %w[id title description dueDay assignee])
        t = task.()
        raise WorkError.new(409, "Сначала восстанови задачу") if t["archivedAt"]
        t.merge!(task_values.(), "updatedAt" => at)
        { "type" => "task", "text" => "Изменена задача: #{t['title']}", "itemId" => t["id"] }
      when "set_task_status"
        fields!(p, %w[id status])
        t = task.()
        raise WorkError.new(400, "Некорректный статус") unless %w[open done].include?(p["status"])
        raise WorkError.new(409, "Сначала восстанови задачу") if t["archivedAt"]
        t["status"] = p["status"]
        t["completedAt"] = p["status"] == "done" ? at : nil
        t["updatedAt"] = at
        { "type" => "task", "text" => "#{p['status'] == 'done' ? 'Выполнена задача: ' : 'Возобновлена задача: '}#{t['title']}", "itemId" => t["id"] }
      when "archive_task", "restore_task"
        fields!(p, %w[id])
        t = task.()
        t["archivedAt"] = body["operation"] == "archive_task" ? at : nil
        t["updatedAt"] = at
        { "type" => "task", "text" => "#{t['archivedAt'] ? 'Скрыта задача: ' : 'Восстановлена задача: '}#{t['title']}", "itemId" => t["id"] }
      when "create_comment"
        fields!(p, %w[text author])
        c = { "id" => SecureRandom.uuid, "text" => string!(p["text"], 5000, true), "author" => nullable!(p["author"], 120),
              "createdAt" => at, "updatedAt" => at, "archivedAt" => nil }
        record["comments"] << c
        { "type" => "comment", "text" => "Добавлен комментарий", "itemId" => c["id"] }
      when "update_comment"
        fields!(p, %w[id text author])
        c = comment.()
        raise WorkError.new(409, "Сначала восстанови комментарий") if c["archivedAt"]
        c["text"] = string!(p["text"], 5000, true)
        c["author"] = nullable!(p["author"], 120)
        c["updatedAt"] = at
        { "type" => "comment", "text" => "Изменён комментарий", "itemId" => c["id"] }
      when "archive_comment", "restore_comment"
        fields!(p, %w[id])
        c = comment.()
        c["archivedAt"] = body["operation"] == "archive_comment" ? at : nil
        c["updatedAt"] = at
        { "type" => "comment", "text" => c["archivedAt"] ? "Скрыт комментарий" : "Восстановлен комментарий", "itemId" => c["id"] }
      else
        raise WorkError.new(400, "Неизвестная операция")
      end
      record["revision"] += 1
      record["updatedAt"] = at
      record["events"] << { "id" => SecureRandom.uuid, "at" => at, **event }
      record
    end

    def summary(record)
      today = Calendar::Slots.moscow_day(Time.current)
      open = record["tasks"].select { |t| !t["archivedAt"] && t["status"] == "open" }
      {
        "revision" => record["revision"] || 0, "owner" => record["owner"], "openTasks" => open.length,
        "overdueTasks" => open.count { |t| t["dueDay"] && t["dueDay"] < today },
        "nextDueDay" => open.filter_map { |t| t["dueDay"] }.min, "lastActivityAt" => record["updatedAt"]
      }
    end
  end
end
