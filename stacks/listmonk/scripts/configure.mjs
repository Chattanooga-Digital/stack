// Runs as the `configure` service. Re-running is safe: it changes only the keys below.
// Mounted alone as a Swarm config, so it imports nothing local.

const SENDER_SETTINGS_KEYS = ["app.root_url", "app.site_name", "app.from_email", "app.message_rate"];

export function buildSettings(current, env) {
  const port = Number(env.SMTP_PORT || 587);
  const tls = env.SMTP_TLS || "STARTTLS";
  const smtp = {
    ...(current.smtp?.[0] ?? {}),
    name: "SendGrid",
    enabled: true,
    host: env.SMTP_HOST,
    port,
    auth_protocol: "login",
    username: env.SMTP_USERNAME,
    password: env.SMTP_PASSWORD,
    tls_type: tls, // none | STARTTLS | TLS
    tls_skip_verify: false,
    max_conns: 5,
    from_addresses: [],
  };
  const next = {
    ...current,
    "app.root_url": env.LISTMONK_ROOT_URL,
    "app.site_name": env.SITE_NAME || "Newsletter",
    "app.from_email": `${env.FROM_NAME} <${env.FROM_EMAIL}>`,
    "app.message_rate": Number(env.SEND_RATE || 10),
    // The public subscribe page would let anyone add an address.
    "app.enable_public_subscription_page": false,
    smtp: [smtp],
    "privacy.unsubscribe_header": true,
  };
  if (env.SENDGRID_WEBHOOK_KEY) {
    next["bounce.enabled"] = true;
    next["bounce.sendgrid_enabled"] = true;
    next["bounce.sendgrid_key"] = env.SENDGRID_WEBHOOK_KEY;
    next["bounce.actions"] = {
      hard: { count: 1, action: "blocklist" },
      complaint: { count: 1, action: "blocklist" },
      soft: { count: 3, action: "none" },
    };
  }
  return next;
}

// The installer seeds sample subscribers, lists and a draft campaign. Each is matched by its seeded
// identity, so anything renamed or sent since is left alone.
export const SAMPLES = {
  emails: ["john@example.com", "anon@example.com"],
  lists: ["Default list", "Opt-in list"],
  campaigns: ["Test campaign"],
};

async function removeSamples(api) {
  const subs = (await api.get(`/api/subscribers?per_page=all&query=${encodeURIComponent(`subscribers.email IN (${SAMPLES.emails.map((e) => `'${e}'`).join(",")})`)}`)).results;
  for (const s of subs) await api.del(`/api/subscribers/${s.id}`);
  const camps = (await api.get("/api/campaigns?per_page=all")).results;
  for (const c of camps) if (SAMPLES.campaigns.includes(c.name) && c.status === "draft") await api.del(`/api/campaigns/${c.id}`);
  const lists = (await api.get("/api/lists?per_page=all")).results;
  for (const l of lists) {
    if (!SAMPLES.lists.includes(l.name)) continue;
    const members = (await api.get(`/api/subscribers?per_page=all&list_id=${l.id}`)).results;
    if (members.every((m) => SAMPLES.emails.includes(m.email))) await api.del(`/api/lists/${l.id}`);
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitHealthy(base, tries = 60) {
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(`${base}/health`);
      if (r.ok) return;
    } catch {
      /* not up yet */
    }
    await sleep(2000);
  }
  throw new Error(`listmonk did not become healthy at ${base}`);
}

async function login(base, user, password) {
  const page = await fetch(`${base}/admin/login`);
  const html = await page.text();
  const nonce = /name="nonce"\s+value="([^"]*)"/.exec(html)?.[1] ?? "";
  const cookies = (page.headers.getSetCookie?.() ?? []).map((c) => c.split(";")[0]);
  const res = await fetch(`${base}/admin/login`, {
    method: "POST",
    redirect: "manual",
    headers: { "content-type": "application/x-www-form-urlencoded", cookie: cookies.join("; ") },
    body: new URLSearchParams({ nonce, next: "/admin", username: user, password }),
  });
  const set = (res.headers.getSetCookie?.() ?? []).map((c) => c.split(";")[0]);
  const jar = [...cookies.filter((c) => !set.some((s) => s.split("=")[0] === c.split("=")[0])), ...set].join("; ");
  if (res.status >= 400 || !jar.includes("session")) throw new Error(`admin login failed (HTTP ${res.status})`);
  return jar;
}

async function main(env) {
  for (const k of ["LISTMONK_URL", "LISTMONK_ROOT_URL", "ADMIN_USER", "ADMIN_PASSWORD", "FROM_EMAIL", "SMTP_HOST", "SMTP_USERNAME", "SMTP_PASSWORD"]) {
    if (!env[k]) throw new Error(`${k} is not set`);
  }
  const base = env.LISTMONK_URL;
  await waitHealthy(base);
  const cookie = await login(base, env.ADMIN_USER, env.ADMIN_PASSWORD);
  const api = {
    get: async (p) => { const r = await fetch(base + p, { headers: { cookie } }); if (!r.ok) throw new Error(`GET ${p.split("?")[0]}: HTTP ${r.status}`); return (await r.json()).data; },
    del: async (p) => { const r = await fetch(base + p, { method: "DELETE", headers: { cookie } }); if (!r.ok) throw new Error(`DELETE ${p}: HTTP ${r.status}`); },
  };
  await removeSamples(api);
  const get = await fetch(`${base}/api/settings`, { headers: { cookie } });
  if (!get.ok) throw new Error(`GET /api/settings: HTTP ${get.status}`);
  const current = (await get.json()).data;
  const put = await fetch(`${base}/api/settings`, {
    method: "PUT",
    headers: { cookie, "content-type": "application/json" },
    body: JSON.stringify(buildSettings(current, env)),
  });
  if (!put.ok) throw new Error(`PUT /api/settings: HTTP ${put.status} ${(await put.text()).slice(0, 200)}`);
  // listmonk restarts itself to load new settings; wait for it, then read back.
  await sleep(3000);
  await waitHealthy(base);
  const cookie2 = await login(base, env.ADMIN_USER, env.ADMIN_PASSWORD);
  const after = (await (await fetch(`${base}/api/settings`, { headers: { cookie: cookie2 } })).json()).data;
  for (const k of SENDER_SETTINGS_KEYS) console.log(`${k} = ${after[k]}`);
  console.log(`smtp host = ${after.smtp?.[0]?.host}, enabled = ${after.smtp?.[0]?.enabled}`);
  console.log(`bounce.sendgrid_enabled = ${after["bounce.sendgrid_enabled"]}`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main(process.env).catch((e) => {
    console.error(`configure failed: ${e.message}`);
    process.exit(1);
  });
}
