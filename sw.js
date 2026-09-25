/* Service worker do app Metal Chinês.
   A CADA ATUALIZAÇÃO no GitHub, aumente o número da VERSAO abaixo (v14 → v15 → v16...). */
const VERSAO = "v14";
const CACHE = "metal-chines-" + VERSAO;
const ARQUIVOS = ["./", "./index.html", "./manifest.webmanifest",
  "./icon-192.png", "./icon-512.png", "./icon-maskable-512.png", "./apple-touch-icon.png"];

self.addEventListener("install", e => {
  // Salva um por um: se algum arquivo faltar no GitHub, o app instala mesmo assim.
  e.waitUntil(caches.open(CACHE)
    .then(c => Promise.all(ARQUIVOS.map(a => c.add(a).catch(() => {}))))
    .then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(caches.keys()
    .then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener("fetch", e => {
  const req = e.request, url = new URL(req.url);
  if (req.method !== "GET" || url.origin !== location.origin) return; // Supabase/CDN: sempre online
  if (req.mode === "navigate") {
    e.respondWith(fetch(req)
      .then(r => { if (r.ok) { const cp = r.clone(); caches.open(CACHE).then(c => c.put("./index.html", cp)); } return r; })
      .catch(() => caches.match("./index.html")));
    return; // só guarda a página se ela veio certa (nunca guarda erro 404)
  }
  e.respondWith(caches.match(req).then(r => r || fetch(req)));
});
