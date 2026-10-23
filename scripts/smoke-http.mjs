// End-to-end HTTP check against a running server (`npm run start`), seeded OWNER required.
// Uses only APP_ORIGIN, OWNER_EMAIL, OWNER_PASSWORD and LEADS_ALLOWED_ORIGINS from the
// environment; submits one synthetic quiz lead; prints no secrets and no personal data.
import { existsSync } from "node:fs";
import { randomInt, randomUUID } from "node:crypto";
import assert from "node:assert/strict";

if (existsSync(".env")) process.loadEnvFile(".env");
const { APP_ORIGIN, OWNER_EMAIL, OWNER_PASSWORD, LEADS_ALLOWED_ORIGINS } =
  process.env;
if (!APP_ORIGIN || !OWNER_EMAIL || !OWNER_PASSWORD || !LEADS_ALLOWED_ORIGINS) {
  console.error(
    "Нужны APP_ORIGIN, OWNER_EMAIL, OWNER_PASSWORD и LEADS_ALLOWED_ORIGINS.",
  );
  process.exit(1);
}
const QUIZ_ORIGIN = LEADS_ALLOWED_ORIGINS.split(",")[0].trim();

const url = (path) => new URL(path, APP_ORIGIN);
const get = (path, cookie) =>
  fetch(url(path), { redirect: "manual", headers: cookie ? { cookie } : {} });
const login = (email, password, origin = APP_ORIGIN) =>
  fetch(url("/api/auth/login"), {
    method: "POST",
    redirect: "manual",
    headers: {
      "content-type": "application/json",
      ...(origin ? { origin } : {}),
    },
    body: JSON.stringify({ email, password }),
  });

const steps = [];
async function step(name, fn) {
  await fn();
  steps.push(name);
  console.log(`ok - ${name}`);
}

let cookie;

await step("health делает SELECT и не раскрывает конфигурацию", async () => {
  const res = await get("/api/health");
  assert.equal(res.status, 200);
  const text = await res.text();
  assert.deepEqual(JSON.parse(text), { status: "ok", database: "up" });
  assert.doesNotMatch(text, /postgres|password|secret/i);
  assert.equal(res.headers.get("x-powered-by"), null);
  assert.equal(res.headers.get("x-frame-options"), "DENY");
});

await step("/crm без сессии перенаправляет на /login", async () => {
  const res = await get("/crm");
  assert.ok([303, 307].includes(res.status), `status ${res.status}`);
  assert.equal(
    new URL(res.headers.get("location"), APP_ORIGIN).pathname,
    "/login",
  );
});

await step("API без сессии отвечает 401", async () => {
  for (const path of ["/api/users", "/api/auth/session", "/api/crm/full?resource=clients", "/api/crm/full-assets"])
    assert.equal((await get(path)).status, 401, path);
});

await step("вход без Origin и с чужим Origin запрещен", async () => {
  assert.equal((await login(OWNER_EMAIL, OWNER_PASSWORD, null)).status, 403);
  assert.equal(
    (await login(OWNER_EMAIL, OWNER_PASSWORD, "http://evil.example")).status,
    403,
  );
});

await step("неверный пароль — 401", async () => {
  assert.equal(
    (await login(OWNER_EMAIL, "definitely-wrong-password")).status,
    401,
  );
});

await step("вход OWNER выдает httpOnly cookie", async () => {
  const res = await login(OWNER_EMAIL, OWNER_PASSWORD);
  assert.equal(res.status, 200);
  const setCookie = res.headers.get("set-cookie") ?? "";
  assert.match(setCookie, /HttpOnly/i);
  assert.match(setCookie, /SameSite=lax/i);
  if (APP_ORIGIN.startsWith("https:"))
    assert.match(setCookie, /^__Host-.*Secure/i);
  cookie = setCookie.split(";")[0];
});

await step(
  "/crm с сессией ведёт в полный интерфейс, список заявок сохраняется",
  async () => {
    const entry = await get("/crm", cookie);
    assert.ok([303, 307].includes(entry.status));
    assert.equal(new URL(entry.headers.get("location"), APP_ORIGIN).pathname, "/crm/full");
    const full = await get("/crm/full", cookie);
    assert.equal(full.status, 200);
    assert.match(await full.text(), /Полная CRM VetPetCare/);
    const shell = await get("/api/crm/full-assets", cookie);
    assert.equal(shell.status, 200);
    assert.equal(shell.headers.get("x-frame-options"), "SAMEORIGIN");
    assert.match(shell.headers.get("content-security-policy") ?? "", /frame-ancestors 'self'/);
    const res = await get("/crm/leads", cookie);
    assert.equal(res.status, 200);
    assert.match(res.headers.get("cache-control") ?? "", /no-store/);
    const html = await res.text();
    assert.match(html, /Заявок пока нет|leads-table/);
    assert.match(html, /<html lang="ru"/);
  },
);

// --- Quiz lead: synthetic data only ---------------------------------------------------------
const phoneDigits = `7999${String(randomInt(0, 10_000_000)).padStart(7, "0")}`;
const lead = {
  last_name: "Смоукова",
  first_name: "Синтетика",
  phone: `+${phoneDigits}`,
  species: "собака",
  consent_pd: true,
  consent_marketing: false,
  quiz_version: "smoke-test",
  idempotency_key: randomUUID(),
  utm: { source: "smoke" },
  page_url: `${QUIZ_ORIGIN}/quiz?name=drop#x`,
  website: "",
};
const postLead = (body, origin = QUIZ_ORIGIN) =>
  fetch(url("/api/leads"), {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(origin ? { origin } : {}),
    },
    body: JSON.stringify(body),
  });
let leadId;

await step("preflight /api/leads разрешен только origin квиза", async () => {
  const ok = await fetch(url("/api/leads"), {
    method: "OPTIONS",
    headers: {
      origin: QUIZ_ORIGIN,
      "access-control-request-method": "POST",
      "access-control-request-headers": "content-type",
    },
  });
  assert.equal(ok.status, 204);
  assert.equal(ok.headers.get("access-control-allow-origin"), QUIZ_ORIGIN);
  const evil = await fetch(url("/api/leads"), {
    method: "OPTIONS",
    headers: {
      origin: "http://evil.example",
      "access-control-request-method": "POST",
    },
  });
  assert.equal(evil.status, 403);
  assert.equal(evil.headers.get("access-control-allow-origin"), null);
});

await step("заявка с чужого, null и без Origin отклоняется", async () => {
  for (const origin of ["http://evil.example", "null", null])
    assert.equal((await postLead(lead, origin)).status, 403);
});

await step(
  "синтетическая заявка создается без сессии и без ПДн в ответе",
  async () => {
    const res = await postLead(lead);
    assert.equal(res.status, 201);
    const text = await res.text();
    const body = JSON.parse(text);
    assert.deepEqual(Object.keys(body).sort(), [
      "booking_token",
      "lead_id",
      "status",
    ]);
    assert.match(body.booking_token, /^[a-f0-9]{64}$/);
    assert.doesNotMatch(text, /Смоукова|Синтетика|7999/);
    leadId = body.lead_id;
  },
);

await step(
  "повтор ключа возвращает тот же lead_id, другие данные — 409",
  async () => {
    const replay = await postLead(lead);
    assert.equal(replay.status, 201);
    assert.equal((await replay.json()).lead_id, leadId);
    assert.equal((await postLead({ ...lead, species: "кошка" })).status, 409);
  },
);

await step("API заявок без сессии отвечает 401", async () => {
  assert.equal((await get("/api/crm/leads")).status, 401);
  assert.equal((await get(`/api/crm/leads/${leadId}`)).status, 401);
  const card = await get(`/crm/leads/${leadId}`);
  assert.ok([303, 307].includes(card.status), `status ${card.status}`);
});

await step("заявка находится в списке по телефону (API и /crm/leads)", async () => {
  const res = await get(`/api/crm/leads?q=${phoneDigits.slice(-7)}`, cookie);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("cache-control"), "no-store");
  const body = await res.json();
  assert.ok(body.rows.some((row) => row.id === leadId));
  const html = await (
    await get(`/crm/leads?q=${phoneDigits.slice(-7)}`, cookie)
  ).text();
  assert.match(html, /Смоукова/);
});

await step("карточка показывает заявку с очищенной страницей", async () => {
  const res = await get(`/crm/leads/${leadId}`, cookie);
  assert.equal(res.status, 200);
  assert.match(res.headers.get("cache-control") ?? "", /no-store/);
  const html = await res.text();
  assert.match(html, /Смоукова/);
  assert.match(html, /Возможные дубли/);
  assert.doesNotMatch(html, /name=drop/);
});

await step("изменение заявки требует Origin и пишется в историю", async () => {
  const current = await (await get(`/api/crm/leads/${leadId}`, cookie)).json();
  const patch = (origin) =>
    fetch(url(`/api/crm/leads/${leadId}`), {
      method: "PATCH",
      headers: {
        cookie,
        "content-type": "application/json",
        ...(origin ? { origin } : {}),
      },
      body: JSON.stringify({
        expectedVersion: current.lead.version,
        status: "IN_PROGRESS",
        comment: "Синтетический smoke-комментарий",
      }),
    });
  assert.equal((await patch(null)).status, 403);
  const res = await patch(APP_ORIGIN);
  assert.equal(res.status, 200);
  assert.equal((await res.json()).lead.status, "IN_PROGRESS");
  const card = await (await get(`/api/crm/leads/${leadId}`, cookie)).json();
  assert.deepEqual(
    card.lead.history.map((entry) => entry.action),
    ["lead.updated", "lead.created"],
  );
});

await step("OWNER получает список пользователей", async () => {
  const res = await get("/api/users", cookie);
  assert.equal(res.status, 200);
  assert.doesNotMatch(await res.text(), /password|argon2/i);
});

await step("выход без Origin запрещен, с Origin отзывает сессию", async () => {
  const blocked = await fetch(url("/api/auth/logout"), {
    method: "POST",
    redirect: "manual",
    headers: { cookie },
  });
  assert.equal(blocked.status, 403);
  const res = await fetch(url("/api/auth/logout"), {
    method: "POST",
    redirect: "manual",
    headers: { cookie, origin: APP_ORIGIN },
  });
  assert.equal(res.status, 303);
  assert.equal(new URL(res.headers.get("location")).pathname, "/login");
  assert.equal((await get("/api/auth/session", cookie)).status, 401);
  assert.ok([303, 307].includes((await get("/crm", cookie)).status));
});

console.log(`\n${steps.length} smoke-проверок пройдено.`);
