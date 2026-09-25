/* Service worker do app Metal Chinês.
   A CADA ATUALIZAÇÃO no GitHub, aumente o número da VERSAO abaixo (v1 → v2 → v3...). */
const VERSAO = "v1";
const CACHE = "metal-chines-" + VERSAO;
const ARQUIVOS = [
  "./", "./index.html", "./manifest.webmanifest",
  "./icons/icon-192.png", "./icons/icon-512.png", "./icons/maskable-512.png",
  "./icons/apple-touch-icon.png", "./icons/favicon-64.png", "./icons/logo-96.png"
];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ARQUIVOS)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", e => {
  const req = e.request;
  const url = new URL(req.url);
  // Supabase, CDN e qualquer coisa de outro domínio: sempre direto da internet (nunca cache).
  if (req.method !== "GET" || url.origin !== location.origin) return;

  // Página: tenta a internet primeiro (pega a versão nova); sem sinal, abre a salva.
  if (req.mode === "navigate") {
    e.respondWith(
      fetch(req)
        .then(r => { const cp = r.clone(); caches.open(CACHE).then(c => c.put("./index.html", cp)); return r; })
        .catch(() => caches.match("./index.html"))
    );
    return;
  }
  // Ícones e manifest: cache primeiro.
  e.respondWith(caches.match(req).then(r => r || fetch(req)));
});
