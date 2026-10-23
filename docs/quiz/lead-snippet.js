// VetPetCare quiz → CRM: submission of a quiz lead to POST /api/leads.
// Plain browser ES module without dependencies; the contract is described in docs/quiz/README.md.
// It is executed against the real route handler by tests/integration/quiz-snippet.test.ts.

const UTM_KEYS = ["source", "medium", "campaign", "content", "term"];
const RETRYABLE = new Set([429, 500, 502, 503, 504]);
const MAX_RETRY_AFTER_SECONDS = 30;
const MAX_REMEMBERED_KEYS = 50;

/** utm_* parameters of the current page (allow-listed keys only). */
export function readUtm(search = globalThis.location?.search ?? "") {
  const params = new URLSearchParams(search);
  const utm = {};
  for (const key of UTM_KEYS) {
    const value = params.get(`utm_${key}`);
    if (value) utm[key] = value.slice(0, 100);
  }
  return utm;
}

/** Page address without query and fragment: they may contain personal data. */
export function currentPageUrl(loc = globalThis.location) {
  return loc ? `${loc.origin}${loc.pathname}` : undefined;
}

function backoffMs(attempt) {
  return Math.min(1000 * 2 ** (attempt - 1), 8000);
}

/**
 * Conservative phone part of the answer signature. Without a phone library the snippet cannot
 * compute E.164, so two inputs share a signature only where the server is certain to produce the
 * same number. Exactly these equivalences are supported:
 * - spaces and the characters ( ) - . are ignored;
 * - "+7XXXXXXXXXX", "8XXXXXXXXXX" and "XXXXXXXXXX" (ten digits, no "+") are one Russian number:
 *   the server reads input without "+" in region RU, where "8" is the trunk prefix.
 * A leading "+" is always significant ("4951234567" is +7 495…, "+4951234567" is +49 51…), and
 * any other form without "+" is compared literally. Different signatures for one real number
 * only cost a new key (at worst a second lead marked as a possible duplicate), never a 409.
 */
export function phoneSignature(raw) {
  const compact = String(raw ?? "").trim().replace(/[\s().-]/g, "");
  if (/^\+\d+$/.test(compact)) return compact;
  if (/^8\d{10}$/.test(compact)) return `+7${compact.slice(1)}`;
  if (/^\d{10}$/.test(compact)) return `+7${compact}`;
  return `literal:${compact}`;
}

/** The answers the server compares for idempotency; names and species are cleaned exactly as the server does. */
function signatureOf(body) {
  const text = (value) => String(value ?? "").normalize("NFC").trim().replace(/\s+/g, " ");
  return JSON.stringify([
    text(body.last_name),
    text(body.first_name),
    phoneSignature(body.phone),
    text(body.species),
    body.consent_pd,
    body.consent_marketing,
    body.quiz_version,
  ]);
}

/**
 * Returns `submit(answers)`.
 *
 * Idempotency keys are remembered per set of answers (not one shared slot), so parallel or
 * interleaved submits never touch each other's key:
 * - every retry inside one call (network error, lost or unreadable 201, 429, 5xx) reuses the
 *   key captured at the start of that call;
 * - a double click with the same answers sends the same key and gets the same lead_id;
 * - a later submit of the same answers — after success or after giving up — reuses the key and
 *   therefore returns the lead that may already exist instead of creating a duplicate
 *   (the memory lives until the page is reloaded; at most 50 answer sets are remembered);
 * - changed answers get their own key; a 409 forgets only the key of those answers, and only
 *   if it is still the current one.
 *
 * answers: { lastName, firstName, phone, species, consentPd, consentMarketing?, website?, utm?, pageUrl? }
 * result:  { ok: true, leadId } | { ok: false, status?, error, fields? }
 */
export function createLeadSubmitter({
  endpoint,
  quizVersion,
  maxAttempts = 4,
  fetchImpl = (...args) => globalThis.fetch(...args),
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  newKey = () => globalThis.crypto.randomUUID(),
}) {
  const keys = new Map();

  function keyFor(signature) {
    let key = keys.get(signature);
    if (!key) {
      key = newKey();
      keys.set(signature, key);
      if (keys.size > MAX_REMEMBERED_KEYS) keys.delete(keys.keys().next().value);
    }
    return key;
  }

  return async function submit(answers) {
    const body = {
      last_name: answers.lastName,
      first_name: answers.firstName,
      phone: answers.phone,
      species: answers.species,
      // Mandatory checkbox: the server rejects anything but `true`.
      consent_pd: answers.consentPd === true,
      // Separate optional checkbox, unchecked by default: only an explicit `true` grants it.
      consent_marketing: answers.consentMarketing === true,
      quiz_version: quizVersion,
      utm: answers.utm ?? readUtm(),
      page_url: answers.pageUrl ?? currentPageUrl(),
      // Honeypot: value of a visually hidden input that people leave empty.
      website: answers.website ?? "",
    };
    const signature = signatureOf(body);
    const key = keyFor(signature);
    body.idempotency_key = key;
    const payload = JSON.stringify(body);

    for (let attempt = 1; ; attempt += 1) {
      let response;
      let created;
      try {
        response = await fetchImpl(endpoint, {
          method: "POST",
          mode: "cors",
          credentials: "omit",
          headers: { "Content-Type": "application/json" },
          body: payload,
        });
        if (response.status === 201) created = await response.json();
      } catch {
        // Network failure or a 201 whose body was lost: retry with the same key.
        if (attempt >= maxAttempts) return { ok: false, error: "network" };
        await sleep(backoffMs(attempt));
        continue;
      }

      if (response.status === 201) {
        if (typeof created?.lead_id === "string") return { ok: true, leadId: created.lead_id };
        if (attempt >= maxAttempts) return { ok: false, error: "network" };
        await sleep(backoffMs(attempt));
        continue;
      }

      if (RETRYABLE.has(response.status) && attempt < maxAttempts) {
        const retryAfter = Number(response.headers.get("Retry-After"));
        if (response.status !== 429 || (retryAfter > 0 && retryAfter <= MAX_RETRY_AFTER_SECONDS)) {
          await sleep(response.status === 429 ? retryAfter * 1000 : backoffMs(attempt));
          continue;
        }
      }

      const error = await response.json().catch(() => ({}));
      if (response.status === 409 && keys.get(signature) === key) keys.delete(signature);
      return { ok: false, status: response.status, error: error.error ?? "unknown", fields: error.fields ?? [] };
    }
  };
}
