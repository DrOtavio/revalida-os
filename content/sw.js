const CACHE = 'revalida-os-web-shell-v1';
const ESSENTIAL = ['./','./index.html','./app.css','./app.js','./icon.svg','./icon-192.png','./icon-512.png','./apple-touch-icon.png','./sound-correct.mp3','./sound-error.mp3','./manifest.webmanifest'];
self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ESSENTIAL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(Promise.all([caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))),self.clients.claim()]));
});
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if(e.request.method!=='GET'||u.origin!==self.location.origin) return;
  if(u.pathname.endsWith('/manifest.json')||u.pathname.includes('/packs/')||u.pathname.includes('/media/')) {
    e.respondWith(fetch(e.request).then(res => { if(res.ok) {const copy=res.clone(); caches.open(CACHE).then(c=>c.put(e.request,copy));}return res; }).catch(async()=> (await caches.match(e.request)) || Response.error()));
    return;
  }
  e.respondWith(fetch(e.request).then(res=> {if(res.ok){const copy=res.clone();caches.open(CACHE).then(c=>c.put(e.request,copy));}return res;}).catch(async()=>(await caches.match(e.request))|| (await caches.match('./index.html')) || Response.error()));
});
