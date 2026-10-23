# Пробное подключение к YCLIENTS: проверка доступа, счётчики, список полей (без вывода персональных данных).
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$cfg = @{}
Get-Content (Join-Path $PSScriptRoot '.env') -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*([^=#]+)=(.*)$') { $cfg[$matches[1].Trim()] = $matches[2].Trim() }
}
$company = $cfg['YCLIENTS_COMPANY_ID']
$headers = @{
  'Accept'        = 'application/vnd.yclients.v2+json'
  'Authorization' = "Bearer $($cfg['YCLIENTS_PARTNER_TOKEN']), User $($cfg['YCLIENTS_USER_TOKEN'])"
}

function Call($method, $path, $body = $null) {
  $p = @{ Method = $method; Uri = "https://api.yclients.ru$path"; Headers = $headers; ContentType = 'application/json; charset=utf-8' }
  if ($PSVersionTable.PSVersion.Major -ge 6) { $p.SkipHeaderValidation = $true }
  if ($body) { $p.Body = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 10)) }
  try { Invoke-RestMethod @p }
  catch {
    Write-Host "  ! $method $path -> HTTP $([int]$_.Exception.Response.StatusCode): $($_.ErrorDetails.Message) $($_.Exception.Message)" -ForegroundColor Yellow
    $null
  }
  Start-Sleep -Milliseconds 300
}
function Keys($o) { if ($o) { ($o.PSObject.Properties.Name) -join ', ' } }

Write-Host "== Филиал $company"
$c = Call GET "/api/v1/company/$company/"
if ($c) { Write-Host "  название: $($c.data.title); город: $($c.data.city); бизнес-тип: $($c.data.business_type_id)" }

Write-Host "== Доступные компании пользователя"
$my = Call GET "/api/v1/companies?my=1&count=100"
if ($my) { $my.data | ForEach-Object { Write-Host "  $($_.id)  $($_.title)" } }

Write-Host "== Сети"
$g = Call GET "/api/v1/groups"
if ($g) { $g.data | ForEach-Object { Write-Host "  сеть $($_.id) $($_.title): филиалов $(@($_.companies).Count)" } }

Write-Host "== Сотрудники"
$s = Call GET "/api/v1/company/$company/staff/"
if ($s) {
  $all = @($s.data)
  Write-Host "  всего: $($all.Count); уволено: $(@($all | ? fired -eq 1).Count); удалено: $(@($all | ? status -eq 1).Count)"
  Write-Host "  поля (новый метод): $(Keys $all[0])"
}
$s2 = Call GET "/api/v1/staff/$company/"
if ($s2) { Write-Host "  поля (устаревший метод): $(Keys @($s2.data)[0])" }
$pos = Call GET "/api/v1/company/$company/staff/positions/"
if ($pos) { Write-Host "  должности: $(@($pos.data | % title) -join '; ')" }

Write-Host "== Клиенты"
$cl = Call POST "/api/v1/company/$company/clients/search" @{ page = 1; page_size = 1 }
if ($cl) {
  Write-Host "  всего клиентов: $($cl.meta.total_count)"
  Write-Host "  поля в search по умолчанию: $(Keys @($cl.data)[0])"
  $id = @($cl.data)[0].id
  if ($id) {
    $one = Call GET "/api/v1/client/$company/$id"
    if ($one) { Write-Host "  поля карточки клиента: $(Keys $one.data)" }
    $f = Call GET "/api/v1/company/$company/clients/files/$id"
    if ($f) { Write-Host "  файлы у первого клиента: $(@($f.data).Count)" }
    $cm = Call GET "/api/v1/company/$company/clients/$id/comments"
    if ($cm) { Write-Host "  комментарии у первого клиента: $(@($cm.data).Count)" }
  }
}
$cf = Call GET "/api/v1/custom_fields/client/$company"
if ($cf) { Write-Host "  доп. поля клиента: $(@($cf.data | % { "$($_.custom_field.title) [$($_.custom_field.type.code)]" }) -join '; ')" }
$cfr = Call GET "/api/v1/custom_fields/record/$company"
if ($cfr) { Write-Host "  доп. поля записи: $(@($cfr.data | % { "$($_.custom_field.title) [$($_.custom_field.type.code)]" }) -join '; ')" }

Write-Host "== Записи"
$rec = Call GET "/api/v1/records/$company`?page=1&count=1&with_deleted=1"
if ($rec) {
  Write-Host "  всего записей: $($rec.meta.total_count)"
  Write-Host "  поля записи: $(Keys @($rec.data)[0])"
}
