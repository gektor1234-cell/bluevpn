"use strict";

for (const element of document.querySelectorAll("[data-release-platform]")) {
  const platform = element.dataset.releasePlatform;
  if (!["android", "windows"].includes(platform)) continue;
  const base = location.hostname === "176-113-81-35.sslip.io"
    ? location.origin : "https://api.greenvpn.pro";
  const url = new URL("/api/v1/updates/manifest", base);
  url.search = new URLSearchParams({ platform, channel: "stable", currentVersion: "0.0.0" });
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  fetch(url, { signal: controller.signal, credentials: "omit", cache: "no-store" })
    .then(response => { if (!response.ok) throw new Error("manifest unavailable"); return response.json(); })
    .then(({ manifest }) => {
      if (!manifest || manifest.platform !== platform || manifest.fileReady !== true ||
          !/^\d+\.\d+\.\d+(?:[+.-][\w.-]+)?$/.test(manifest.latestVersion)) {
        throw new Error("invalid manifest");
      }
      const build = String(manifest.buildNumber || "");
      element.textContent = `Версия ${manifest.latestVersion}${/^\d+$/.test(build) && !manifest.latestVersion.includes("+") ? `, сборка ${build}` : ""}.`;
    })
    .catch(() => { element.textContent = "Не удалось уточнить версию. Требования к системе указаны выше."; })
    .finally(() => clearTimeout(timer));
}
