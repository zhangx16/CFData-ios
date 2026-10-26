const { webkit, chromium } = require(
  process.env.CFDATA_PLAYWRIGHT_MODULE || "playwright",
);
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const http = require("node:http");
const root = path.resolve(__dirname, "..");
const out =
  process.env.CFDATA_UI_OUTPUT || path.resolve(root, "../build/ui-checks");
fs.mkdirSync(out, { recursive: true });
const server = http.createServer((req, res) => {
  if (req.url === "/" || req.url === "/index.html") {
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    res.end(fs.readFileSync(path.join(root, "web/index.html")));
  } else {
    res.statusCode = 404;
    res.end();
  }
});
let base, browser;
const mock = () => {
  window.__sent = [];
  window.__native = [];
  window.webkit = {
    messageHandlers: {
      cfdata: { postMessage: (m) => window.__native.push(m) },
    },
  };
  class Socket {
    static OPEN = 1;
    constructor() {
      this.readyState = 1;
      window.__socket = this;
      setTimeout(() => {
        this.onopen?.();
        this.receive("init_config", {
          version: "dev",
          speedTestURL: "auto",
          proxyStatus: { configured: false },
        });
      }, 40);
    }
    send(s) {
      window.__sent.push(JSON.parse(s));
    }
    close() {
      this.readyState = 3;
    }
    receive(type, data) {
      this.onmessage?.({ data: JSON.stringify({ type, data }) });
    }
  }
  window.WebSocket = Socket;
  window.__receive = (type, data) => window.__socket.receive(type, data);
};
const raw = (ip, lat) => ({
  IP: ip,
  Port: 443,
  DataCenter: "HKG",
  City: "香港",
  Region: "亚太",
  TCPDuration: lat * 1e6,
  MinLatency: lat * 1e6,
  MaxLatency: (lat + 5) * 1e6,
  AvgLatency: lat * 1e6,
  LossRate: 0,
  Speed: "",
});
(async () => {
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  base = "http://127.0.0.1:" + server.address().port;
  browser = await (
    process.env.CFDATA_BROWSER === "chromium" ? chromium : webkit
  ).launch();
  const page = await browser.newPage({
    viewport: { width: 375, height: 812 },
    deviceScaleFactor: 1,
    isMobile: true,
    hasTouch: true,
  });
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.addInitScript(mock);
  await page.goto(base + "/index.html");
  await page.waitForTimeout(200);
  await page.screenshot({ path: out + "/scan-375.png" });
  assert.equal(await page.locator("body").evaluate((e) => e.scrollWidth), 375);
  await page.locator("#startButton").click();
  assert.equal(await page.evaluate(() => __sent.at(-1).type), "start_task");
  await page.evaluate(
    (rows) => {
      for (const r of rows) __receive("scan_result", r);
      __receive("scan_progress", { current: 20, total: 100 });
      __receive("scan_complete_wait_dc", [
        { DataCenter: "HKG", City: "香港", IPCount: 2, MinLatency: 26 },
      ]);
      __receive("task_complete");
    },
    [raw("104.16.1.1", 26), raw("104.16.2.2", 42)],
  );
  assert.equal(await page.evaluate(() => __sent.at(-1).type), "start_test");
  await page.evaluate(
    (rows) => {
      rows.forEach((r) => __receive("test_result", r));
      __receive("test_complete", rows);
      __receive("task_complete");
    },
    [raw("104.16.1.1", 26), raw("104.16.2.2", 42)],
  );
  assert.equal(
    await page.evaluate(() => __sent.at(-1).type),
    "start_official_speed_batch",
  );
  await page.evaluate(() => {
    __receive("speed_test_result", { ip: "104.16.1.1", speed: "12.80 MB/s" });
    __receive("official_speed_complete", { qualified: 1 });
    __receive("task_complete");
  });
  await page.waitForTimeout(250);
  assert.equal(await page.locator("#page-results").isVisible(), true);
  assert.equal(await page.locator(".result-card").count(), 2);
  await page.screenshot({ path: out + "/results-375.png" });
  await page.locator("#openFilters").click();
  await page.locator("#filterDelay").fill("30");
  await page.locator("#applyFilters").click();
  assert.equal(await page.locator(".result-card").count(), 1);
  await page.locator("#openExport").click();
  await page.locator('[data-export="csv"]').click();
  const exported = await page.evaluate(() =>
    __native.filter((m) => m.type === "export").at(-1),
  );
  assert.ok(exported.content.includes("104.16.1.1"));
  assert.ok(!exported.content.includes("104.16.2.2"));
  await page.locator("[data-copy]").first().click();
  assert.equal(await page.evaluate(() => __native.at(-1).type), "copy");
  await page.locator("#openFilters").click();
  await page.locator("#resetFilters").click();
  await page.locator('.tabbar [data-go="settings"]').click();
  await page.locator("#speedSource").selectOption("custom");
  await page.locator("#speedURL").fill("https://speed.example.net/test.bin");
  await page.locator('.tabbar [data-go="results"]').click();
  await page.locator("[data-speed]").first().click();
  assert.equal(
    await page.evaluate(() => __sent.at(-1).type),
    "start_speed_test",
  );
  assert.equal(
    await page.evaluate(() => __sent.at(-1).data.url),
    "https://speed.example.net/test.bin",
  );
  await page.evaluate(() => {
    __receive("speed_test_result", { ip: "104.16.1.1", speed: "12.80 MB/s" });
    __receive("task_complete");
  });
  await page.locator("#openFilters").focus();
  await page.keyboard.press("Enter");
  assert.equal(await page.locator("#filterSheet").isVisible(), true);
  await page.keyboard.press("Escape");
  assert.equal(await page.locator("#filterSheet").isVisible(), false);
  assert.equal(
    await page
      .locator("#openFilters")
      .evaluate((el) => document.activeElement === el),
    true,
  );
  await page.locator('.tabbar [data-go="scan"]').click();
  await page.locator('[data-mode="custom"]').click();
  await page.locator("#targets").fill("1.1.1.1 443\n[2606:4700::1111] 443");
  await page.locator("#startButton").click();
  assert.equal(await page.evaluate(() => __sent.at(-1).type), "start_nsb_task");
  assert.equal(await page.evaluate(() => __sent.at(-1).data.speedTest), 1);
  await page.evaluate(() => {
    __receive("nsb_scan_result", {
      ip: "2606:4700::1111",
      port: "443",
      dc: "HKG",
      city: "香港",
      latency: "18.2 ms",
      lossRate: "0%",
      speed: "8.40MB/s",
    });
    __receive("task_complete");
  });
  await page.waitForTimeout(250);
  assert.equal(await page.locator(".result-card").count(), 1);
  await page.locator("[data-copy]").click();
  assert.equal(
    await page.evaluate(() => __native.at(-1).text),
    "[2606:4700::1111]:443",
  );
  await page.locator('.tabbar [data-go="settings"]').click();
  await page.locator("#theme").selectOption("dark");
  await page.locator("#toast").waitFor({ state: "hidden" });
  await page.screenshot({ path: out + "/settings-dark-375.png" });
  await page.reload();
  await page.waitForTimeout(250);
  await page.locator('.tabbar [data-go="results"]').click();
  assert.equal(await page.locator(".result-card").count(), 1);
  await page.locator('.tabbar [data-go="scan"]').click();
  await page.locator('[data-mode="official"]').click();
  await page.locator("#startButton").click();
  await page.evaluate(() => CFData.didForeground());
  assert.equal(await page.evaluate(() => __sent.at(-1).type), "stop_task");
  await page.evaluate(() => __receive("task_stopped"));
  assert.ok((await page.locator("#startLabel").textContent()).includes("开始"));
  for (const width of [320, 375, 390, 430, 767, 768, 1280]) {
    await page.setViewportSize({ width, height: 900 });
    for (const tab of ["scan", "results", "settings"]) {
      await page.locator(`.tabbar [data-go="${tab}"]`).click();
      const overflow = await page.evaluate(
        () => document.documentElement.scrollWidth > innerWidth,
      );
      assert.equal(overflow, false, `${width} ${tab} overflow`);
      await page
        .locator(`#page-${tab} details`)
        .evaluateAll((nodes) => nodes.forEach((el) => (el.open = true)));
      assert.equal(
        await page.evaluate(
          () => document.documentElement.scrollWidth > innerWidth,
        ),
        false,
        `${width} ${tab} expanded overflow`,
      );
      const undersized = await page
        .locator("button,input,select,textarea,summary,a[href]")
        .evaluateAll((nodes) =>
          nodes
            .filter((el) => {
              if (!el.checkVisibility()) return false;
              const box = (el.closest("label") || el).getBoundingClientRect();
              return box.width < 24 || box.height < 24;
            })
            .map((el) => el.id || el.textContent.slice(0, 30)),
        );
      assert.deepEqual(
        undersized,
        [],
        `${width} ${tab} undersized touch targets`,
      );
      await page
        .locator(`#page-${tab} details`)
        .evaluateAll((nodes) => nodes.forEach((el) => (el.open = false)));
    }
  }
  assert.deepEqual(errors, []);
  console.log(
    `${process.env.CFDATA_BROWSER || "webkit"}: automatic scan → latency → speed, updated speed source, custom IPv6 input, stop-on-foreground, filtering, native export/copy, persistence, keyboard dialogs, touch targets and 7 responsive widths passed.`,
  );
})()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(async () => {
    await browser?.close();
    server.close();
  });
