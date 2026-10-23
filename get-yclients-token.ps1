# Получение ключей YCLIENTS и запись их в .env (запускать самому, в своём терминале).
# Пароль никуда не сохраняется — используется только для одного запроса к api.yclients.ru.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$envPath = Join-Path $PSScriptRoot '.env'

function Read-Secret($prompt) {
  [Net.NetworkCredential]::new('', (Read-Host $prompt -AsSecureString)).Password
}

function Invoke-Auth($body) {
  $bytes = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json))
  try {
    Invoke-RestMethod -Method Post -Uri 'https://api.yclients.ru/api/v1/auth' -Headers $headers `
      -ContentType 'application/json; charset=utf-8' -Body $bytes
  } catch {
    $status = $_.Exception.Response.StatusCode.value__
    Write-Host "Ошибка HTTP $status. Ответ YCLIENTS:" -ForegroundColor Red
    Write-Host $_.ErrorDetails.Message
    exit 1
  }
}

$partner  = (Read-Secret 'Partner token (из кабинета разработчика YCLIENTS)').Trim() -replace '^Bearer\s+', ''
$login    = (Read-Host  'Логин YCLIENTS (телефон или email)').Trim()
$password = Read-Secret 'Пароль YCLIENTS'
$company  = (Read-Host  'ID филиала (только цифры из адреса yclients.com/timetable/<ID>)') -replace '\D', ''

Write-Host "Длина partner token: $($partner.Length) символов"

$headers = @{
  'Accept'        = 'application/vnd.yclients.v2+json'
  'Authorization' = "Bearer $partner"
}
$body = @{ login = $login; password = $password }

$r = Invoke-Auth $body

if (-not $r.data.user_token -and $r.data.uuid) {
  Write-Host "Включена 2FA: код отправлен ($($r.data.transport.type): $($r.data.transport.recipient))"
  $code = Read-Host 'Код подтверждения'
  $body['2fa'] = @{ uuid = $r.data.uuid; secret = $code.Trim() }
  $r = Invoke-Auth $body
}

$userToken = $r.data.user_token
if (-not $userToken) { throw "Не удалось получить user_token. Ответ: $($r | ConvertTo-Json -Depth 5 -Compress)" }

@"
YCLIENTS_PARTNER_TOKEN=$partner
YCLIENTS_USER_TOKEN=$userToken
YCLIENTS_COMPANY_ID=$company
"@ | Set-Content -Path $envPath -Encoding utf8

Write-Host "Готово: ключи записаны в $envPath (пользователь: $($r.data.name))"