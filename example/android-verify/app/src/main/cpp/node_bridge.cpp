#include <arpa/inet.h>
#include <android/log.h>
#include <fcntl.h>
#include <jni.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include "cppgc/platform.h"
#include "node.h"

#include <atomic>
#include <chrono>
#include <cctype>
#include <fstream>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

using node::CommonEnvironmentSetup;
using node::Environment;
using node::MultiIsolatePlatform;
using v8::Context;
using v8::HandleScope;
using v8::Isolate;
using v8::Locker;
using v8::MaybeLocal;
using v8::V8;
using v8::Value;

namespace {

constexpr const char* kTag = "NodeVerify";

std::mutex g_node_mutex;
bool g_process_initialized = false;
bool g_process_failed = false;
std::string g_process_error;
std::unique_ptr<MultiIsolatePlatform> g_platform;
std::vector<std::string> g_exec_args;
std::mutex g_http_server_mutex;
std::atomic<bool> g_http_server_running{false};
std::atomic<bool> g_http_server_starting{false};
std::atomic<int> g_http_server_port{0};
std::string g_http_server_ready_path;
std::string g_http_server_error_path;

constexpr int kHttpServerPort = 8123;

using NodeItems = std::vector<std::pair<std::string, std::string>>;

bool EnsureNodeProcessInitialized(std::string* detail);

std::string EscapeJsString(const std::string& value) {
  std::string out;
  out.reserve(value.size() + 16);
  for (char ch : value) {
    switch (ch) {
      case '\\':
        out += "\\\\";
        break;
      case '\'':
        out += "\\'";
        break;
      case '\n':
        out += "\\n";
        break;
      case '\r':
        out += "\\r";
        break;
      case '\t':
        out += "\\t";
        break;
      default:
        out.push_back(ch);
        break;
    }
  }
  return out;
}

std::string EscapeJsonString(const std::string& value) {
  std::string out;
  out.reserve(value.size() + 16);
  for (char ch : value) {
    switch (ch) {
      case '\\':
        out += "\\\\";
        break;
      case '"':
        out += "\\\"";
        break;
      case '\n':
        out += "\\n";
        break;
      case '\r':
        out += "\\r";
        break;
      case '\t':
        out += "\\t";
        break;
      default:
        out.push_back(ch);
        break;
    }
  }
  return out;
}

void ReplaceAll(std::string* text,
                const std::string& needle,
                const std::string& replacement) {
  size_t pos = 0;
  while ((pos = text->find(needle, pos)) != std::string::npos) {
    text->replace(pos, needle.size(), replacement);
    pos += replacement.size();
  }
}

std::string Trim(const std::string& value) {
  size_t start = 0;
  while (start < value.size() &&
         std::isspace(static_cast<unsigned char>(value[start]))) {
    ++start;
  }

  size_t end = value.size();
  while (end > start &&
         std::isspace(static_cast<unsigned char>(value[end - 1]))) {
    --end;
  }

  return value.substr(start, end - start);
}

std::string ReadFileIfExists(const std::string& path) {
  std::ifstream in(path);
  if (!in) return {};
  std::ostringstream ss;
  ss << in.rdbuf();
  return ss.str();
}

std::string BuildErrorJson(const std::string& mode,
                           const std::string& headline,
                           const std::string& summary,
                           const std::string& detail) {
  std::ostringstream out;
  out << "{"
      << "\"kind\":\"" << (mode == "report" ? "report" : "action") << "\","
      << "\"status\":\"error\","
      << "\"mode\":\"" << EscapeJsonString(mode) << "\","
      << "\"headline\":\"" << EscapeJsonString(headline) << "\","
      << "\"summary\":\"" << EscapeJsonString(summary) << "\","
      << "\"generatedAt\":\"\","
      << "\"nodeVersion\":\"?\","
      << "\"platform\":\"android\","
      << "\"arch\":\"arm64-v8a\","
      << "\"icuStatus\":\"ICU unavailable\","
      << "\"stats\":[],"
      << "\"highlights\":[],"
      << "\"checks\":[],"
      << "\"artifacts\":[],"
      << "\"sections\":[],"
      << "\"items\":[{\"label\":\"detail\",\"value\":\"" << EscapeJsonString(detail)
      << "\"}]"
      << "}";
  return out.str();
}

std::string BuildActionJson(const std::string& mode,
                            const std::string& title,
                            const std::string& summary,
                            const NodeItems& items,
                            const std::string& status = "success") {
  std::ostringstream out;
  out << "{"
      << "\"kind\":\"action\","
      << "\"status\":\"" << EscapeJsonString(status) << "\","
      << "\"mode\":\"" << EscapeJsonString(mode) << "\","
      << "\"title\":\"" << EscapeJsonString(title) << "\","
      << "\"summary\":\"" << EscapeJsonString(summary) << "\","
      << "\"generatedAt\":\"\","
      << "\"nodeVersion\":\"?\","
      << "\"platform\":\"android\","
      << "\"arch\":\"arm64-v8a\","
      << "\"icuStatus\":\"\","
      << "\"items\":[";
  for (size_t index = 0; index < items.size(); ++index) {
    if (index > 0) out << ",";
    out << "{"
        << "\"label\":\"" << EscapeJsonString(items[index].first) << "\","
        << "\"value\":\"" << EscapeJsonString(items[index].second) << "\""
        << "}";
  }
  out << "]"
      << "}";
  return out.str();
}

std::string BuildReportScript(const std::string& files_dir,
                              const std::string& proof_path) {
  std::string script = R"JS(
(async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const crypto = require('node:crypto');
  const zlib = require('node:zlib');
  const { URL } = require('node:url');
  const { EventEmitter, once } = require('node:events');
  const { setTimeout: sleep } = require('node:timers/promises');
  const fsPromises = require('node:fs/promises');

  process.chdir('__FILES_DIR__');

  const filesDir = '__FILES_DIR__';
  const proofPath = '__PROOF_PATH__';
  const sampleText = 'Node.js runtime on Android, rendered through an interactive Compose dashboard.';
  const sampleBuffer = Buffer.from(sampleText, 'utf8');
  const digest = crypto.createHash('sha256').update(sampleBuffer).digest('hex');
  const url = new URL(`https://node.android.demo:8443/runtime?icu=${encodeURIComponent(process.versions.icu || 'none')}&arch=${encodeURIComponent(process.arch)}&module=${encodeURIComponent(process.versions.modules || 'unknown')}`);
  const checks = [];
  const highlights = [];

  const addCheck = (id, title, ok, detail) => checks.push({ id, title, ok, detail });

  fs.writeFileSync(proofPath, sampleBuffer);
  const proofReadback = fs.readFileSync(proofPath, 'utf8');
  const stat = fs.statSync(proofPath);
  const compressed = zlib.gzipSync(sampleBuffer);
  const roundTrip = zlib.gunzipSync(compressed).toString('utf8');

  const emitter = new EventEmitter();
  setTimeout(() => emitter.emit('ready', 'event-loop-ok'), 18);
  const [eventValue] = await once(emitter, 'ready');
  const timerStart = Date.now();
  await sleep(24);
  const timerDelayMs = Date.now() - timerStart;

  const localesToProbe = ['zh-CN', 'ar-EG', 'hi-IN', 'fr-FR', 'de-DE'];
  const supportedLocales = Intl.DateTimeFormat.supportedLocalesOf(localesToProbe);
  const hasSegmenter = typeof Intl.Segmenter === 'function';
  const segmentCount = hasSegmenter
    ? Array.from(new Intl.Segmenter('zh-CN', { granularity: 'word' }).segment('Node.js在安卓上稳定运行')).length
    : 0;
  const utcExample = new Intl.DateTimeFormat('zh-CN', {
    dateStyle: 'full',
    timeStyle: 'long',
    timeZone: 'UTC'
  }).format(new Date('2026-04-05T00:00:00Z'));
  const icuStatus = process.versions.icu
    ? `ICU ${process.versions.icu} / locales ${supportedLocales.length}/${localesToProbe.length}${hasSegmenter ? ' / Segmenter ok' : ''}`
    : 'ICU unavailable';

  const generatedAt = new Date().toISOString();

  addCheck('boot', 'Node runtime booted', true, `Node ${process.versions.node} launched via libnode.so`);
  addCheck('fs', 'Filesystem write and readback', proofReadback === sampleText, `proof bytes=${stat.size}`);
  addCheck('crypto', 'Crypto digest and UUID', digest.length === 64 && typeof crypto.randomUUID() === 'string', `sha256=${digest.slice(0, 12)}...`);
  addCheck('zlib', 'gzip roundtrip', roundTrip === sampleText, `compressed=${compressed.byteLength} bytes`);
  addCheck('async', 'Event loop advanced', eventValue === 'event-loop-ok' && timerDelayMs >= 20, `timer=${timerDelayMs}ms`);
  addCheck('intl', 'Full ICU locale coverage', supportedLocales.length >= 4 && Boolean(process.versions.icu), `supported=${supportedLocales.join(', ')}`);

  const passedChecks = checks.filter((item) => item.ok).length;
  const totalChecks = checks.length;
  const healthPercent = Math.round((passedChecks / totalChecks) * 100);

  highlights.push(
    `Node ${process.versions.node} with V8 ${process.versions.v8}`,
    `${passedChecks}/${totalChecks} verification checks passed`,
    `Full ICU signal: ${icuStatus}`
  );

  console.log(JSON.stringify({
    kind: 'report',
    mode: 'report',
    status: passedChecks === totalChecks ? 'success' : 'degraded',
    headline: 'Interactive Node.js verification running on Android',
    summary: 'The embedded libnode runtime completed a full verification pass and exported structured results for the Compose dashboard.',
    nodeVersion: process.versions.node,
    platform: process.platform,
    arch: process.arch,
    icuStatus,
    generatedAt,
    stats: [
      { label: 'Node', value: process.versions.node },
      { label: 'Arch', value: process.arch },
      { label: 'Checks', value: `${passedChecks}/${totalChecks}` },
      { label: 'Health', value: `${healthPercent}%` }
    ],
    highlights,
    checks,
    items: []
  }));
})().catch((error) => {
  console.log(JSON.stringify({
    kind: 'report',
    mode: 'report',
    status: 'error',
    headline: 'Node.js started but the verification script failed',
    summary: 'The embedded runtime launched, but one of the feature probes threw before the structured report was completed.',
    generatedAt: new Date().toISOString(),
    nodeVersion: process.versions?.node || '?',
    platform: process.platform || 'android',
    arch: process.arch || 'arm64-v8a',
    icuStatus: process.versions?.icu ? `ICU ${process.versions.icu}` : 'ICU unavailable',
    stats: [],
    highlights: [],
    checks: [],
    items: [
      { label: 'stack', value: String(error?.stack || 'No stack available') }
    ]
  }));
});
)JS";

  ReplaceAll(&script, "__FILES_DIR__", EscapeJsString(files_dir));
  ReplaceAll(&script, "__PROOF_PATH__", EscapeJsString(proof_path));
  return script;
}

std::string BuildActionScript(const std::string& mode,
                              const std::string& payload_json,
                              const std::string& files_dir) {
  std::string script = R"JS(
(async () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const os = require('node:os');
  const crypto = require('node:crypto');
  const zlib = require('node:zlib');
  const { URL } = require('node:url');
  const { setTimeout: sleep } = require('node:timers/promises');

  process.chdir('__FILES_DIR__');

  const filesDir = '__FILES_DIR__';
  const mode = '__MODE__';
  const payload = JSON.parse('__PAYLOAD_JSON__');
  const text = String(payload.text ?? 'Node.js on Android');
  const locale = String(payload.locale ?? 'zh-CN');
  const result = {
    kind: 'action',
    mode,
    status: 'success',
    title: '',
    summary: '',
    generatedAt: new Date().toISOString(),
    nodeVersion: process.versions.node,
    platform: process.platform,
    arch: process.arch,
    icuStatus: process.versions.icu ? `ICU ${process.versions.icu}` : 'ICU unavailable',
    items: []
  };

  if (mode === 'crypto') {
    const hash = crypto.createHash('sha256').update(text).digest('hex');
    result.title = 'Crypto Playground';
    result.summary = 'Node generated digest material from your current input.';
    result.items.push(
      { label: 'Input bytes', value: String(Buffer.byteLength(text)) },
      { label: 'randomUUID', value: crypto.randomUUID() },
      { label: 'sha256', value: hash },
      { label: 'Buffer preview', value: Buffer.from(text).subarray(0, 16).toString('hex') }
    );
  } else if (mode === 'gzip') {
    const compressed = zlib.gzipSync(Buffer.from(text, 'utf8'));
    const inflated = zlib.gunzipSync(compressed).toString('utf8');
    result.title = 'Compression Playground';
    result.summary = 'Node compressed and decompressed your text through zlib.';
    result.items.push(
      { label: 'Original bytes', value: String(Buffer.byteLength(text)) },
      { label: 'gzip bytes', value: String(compressed.byteLength) },
      { label: 'Roundtrip matches', value: String(inflated === text) },
      { label: 'gzip ratio', value: `${Math.round((compressed.byteLength / Math.max(1, Buffer.byteLength(text))) * 100)}%` }
    );
  } else if (mode === 'fs') {
    const actionPath = path.join(filesDir, 'node-playground-note.txt');
    fs.writeFileSync(actionPath, text, 'utf8');
    const readback = fs.readFileSync(actionPath, 'utf8');
    result.title = 'Filesystem Playground';
    result.summary = 'Node wrote your current input to app storage and loaded it back.';
    result.items.push(
      { label: 'File path', value: actionPath },
      { label: 'Basename', value: path.basename(actionPath) },
      { label: 'Readback matches', value: String(readback === text) },
      { label: 'Stored preview', value: readback.slice(0, 120) }
    );
  } else if (mode === 'intl') {
    const formatter = new Intl.DateTimeFormat(locale, {
      dateStyle: 'full',
      timeStyle: 'long',
      timeZone: 'UTC'
    });
    const nf = new Intl.NumberFormat(locale);
    const hasSegmenter = typeof Intl.Segmenter === 'function';
    const segmentCount = hasSegmenter
      ? Array.from(new Intl.Segmenter(locale, { granularity: 'word' }).segment(text)).length
      : 0;
    result.title = 'Intl Playground';
    result.summary = 'Node applied ICU-backed formatting using your chosen locale.';
    result.items.push(
      { label: 'Locale', value: locale },
      { label: 'Formatted UTC date', value: formatter.format(new Date('2026-04-05T00:00:00Z')) },
      { label: 'Formatted number', value: nf.format(9876543.21) },
      { label: 'Intl.Segmenter count', value: String(segmentCount) }
    );
  } else if (mode === 'url') {
    const source = text.includes('://') ? text : `https://node.android.demo/runtime?q=${encodeURIComponent(text)}`;
    const parsed = new URL(source);
    result.title = 'URL Playground';
    result.summary = 'Node parsed your current input through the WHATWG URL implementation.';
    result.items.push(
      { label: 'href', value: parsed.href },
      { label: 'host', value: parsed.host },
      { label: 'pathname', value: parsed.pathname },
      { label: 'search', value: parsed.search || '(empty)' }
    );
  } else if (mode === 'timers') {
    const start = Date.now();
    await sleep(35);
    const delay = Date.now() - start;
    result.title = 'Timer Playground';
    result.summary = 'Node awaited a timer inside the Android app process.';
    result.items.push(
      { label: 'Observed delay', value: `${delay}ms` },
      { label: 'tmpdir', value: os.tmpdir() },
      { label: 'uptime sample', value: `${process.uptime().toFixed(3)}s` },
      { label: 'Input echo', value: text.slice(0, 80) }
    );
  } else {
    result.status = 'error';
    result.title = 'Unknown action';
    result.summary = `Mode ${mode} is not implemented.`;
    result.items.push({ label: 'mode', value: mode });
  }

  console.log(JSON.stringify(result));
})().catch((error) => {
  console.log(JSON.stringify({
    kind: 'action',
    mode: '__MODE__',
    status: 'error',
    title: 'Node action failed',
    summary: `${error?.name || 'Error'}: ${error?.message || 'Unknown failure'}`,
    generatedAt: new Date().toISOString(),
    nodeVersion: process.versions?.node || '?',
    platform: process.platform || 'android',
    arch: process.arch || 'arm64-v8a',
    icuStatus: process.versions?.icu ? `ICU ${process.versions.icu}` : 'ICU unavailable',
    items: [
      { label: 'stack', value: String(error?.stack || 'No stack available') }
    ]
  }));
});
)JS";

  ReplaceAll(&script, "__MODE__", EscapeJsString(mode));
  ReplaceAll(&script, "__PAYLOAD_JSON__", EscapeJsString(payload_json));
  ReplaceAll(&script, "__FILES_DIR__", EscapeJsString(files_dir));
  return script;
}

std::string BuildHttpServerScript(int port,
                                  const std::string& files_dir,
                                  const std::string& ready_path,
                                  const std::string& error_path) {
  std::string script = R"JS(
(async () => {
  const fs = require('node:fs');
  const http = require('node:http');

  process.chdir('__FILES_DIR__');

  const readyPath = '__READY_PATH__';
  const errorPath = '__ERROR_PATH__';
  const port = __PORT__;
  let requestCount = 0;

  const persistError = (error) => {
    try {
      fs.writeFileSync(errorPath, String(error?.stack || error || 'Unknown server failure'), 'utf8');
    } catch {}
  };

  process.on('uncaughtException', (error) => {
    persistError(error);
  });

  process.on('unhandledRejection', (error) => {
    persistError(error);
  });

  const server = http.createServer((req, res) => {
    requestCount += 1;

    if (req.url === '/shutdown') {
      const payload = {
        ok: true,
        state: 'stopping',
        requestCount,
        now: new Date().toISOString()
      };
      res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify(payload));
      setTimeout(() => {
        server.close();
      }, 30);
      return;
    }

    const payload = {
      ok: true,
      route: req.url,
      method: req.method,
      requestCount,
      node: process.versions.node,
      now: new Date().toISOString(),
      uptimeSeconds: Number(process.uptime().toFixed(3))
    };
    res.writeHead(200, {
      'content-type': 'application/json; charset=utf-8',
      'x-node-android': '1'
    });
    res.end(JSON.stringify(payload));
  });

  server.on('error', (error) => {
    persistError(error);
  });

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', () => {
      fs.writeFileSync(readyPath, JSON.stringify({
        ok: true,
        url: `http://127.0.0.1:${port}/`,
        stopUrl: `http://127.0.0.1:${port}/shutdown`,
        startedAt: new Date().toISOString()
      }), 'utf8');
      resolve();
    });
  });

  await new Promise((resolve) => {
    server.on('close', resolve);
  });
})().catch((error) => {
  try {
    require('node:fs').writeFileSync('__ERROR_PATH__', String(error?.stack || error), 'utf8');
  } catch {}
});
)JS";

  ReplaceAll(&script, "__FILES_DIR__", EscapeJsString(files_dir));
  ReplaceAll(&script, "__READY_PATH__", EscapeJsString(ready_path));
  ReplaceAll(&script, "__ERROR_PATH__", EscapeJsString(error_path));
  ReplaceAll(&script, "__PORT__", std::to_string(port));
  return script;
}

bool WaitForFile(const std::string& path, int timeout_ms) {
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout_ms);
  while (std::chrono::steady_clock::now() < deadline) {
    if (access(path.c_str(), F_OK) == 0) {
      return true;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }
  return access(path.c_str(), F_OK) == 0;
}

bool RunHttpServerLoop(const std::string& script) {
  std::vector<std::string> args = {
      "nodeverify",
      node::GetAnonymousMainPath(),
  };
  std::vector<std::string> errors;

  std::unique_ptr<CommonEnvironmentSetup> setup =
      CommonEnvironmentSetup::Create(g_platform.get(), &errors, args, g_exec_args);

  if (!setup) {
    std::ostringstream err;
    for (const std::string& part : errors) {
      if (!err.str().empty()) err << " | ";
      err << part;
    }
    if (!g_http_server_error_path.empty()) {
      std::ofstream out(g_http_server_error_path, std::ios::trunc);
      out << (err.str().empty() ? "CommonEnvironmentSetup::Create() returned null." : err.str());
    }
    return false;
  }

  Isolate* isolate = setup->isolate();
  Environment* env = setup->env();

  Locker locker(isolate);
  Isolate::Scope isolate_scope(isolate);
  HandleScope handle_scope(isolate);
  Context::Scope context_scope(setup->context());

  node::SetProcessExitHandler(env, [](Environment* environment, int) {
    node::Stop(environment);
  });

  MaybeLocal<Value> loadenv_ret = node::LoadEnvironment(env, script);
  if (!loadenv_ret.IsEmpty()) {
    node::SpinEventLoop(env).FromMaybe(1);
  }

  node::Stop(env);
  return true;
}

bool EnsureNodeProcessInitializedForHttp(std::string* detail) {
  std::lock_guard<std::mutex> lock(g_node_mutex);
  return EnsureNodeProcessInitialized(detail);
}

std::string StartHttpServer(const std::string& files_dir,
                            const std::string& cache_dir) {
  {
    std::lock_guard<std::mutex> lock(g_http_server_mutex);
    if (g_http_server_running.load()) {
      return BuildActionJson(
          "http-server-start",
          "HTTP server already running",
          "The existing Node HTTP server is still serving requests.",
          {
              {"State", "running"},
              {"Endpoint", "http://127.0.0.1:" + std::to_string(g_http_server_port.load()) + "/"},
              {"Stop route", "/shutdown"},
          });
    }
    if (g_http_server_starting.load()) {
      return BuildActionJson(
          "http-server-start",
          "HTTP server is starting",
          "The Node HTTP server is still booting.",
          {
              {"State", "starting"},
              {"Endpoint", "http://127.0.0.1:" + std::to_string(kHttpServerPort) + "/"},
          });
    }

    g_http_server_starting = true;
    g_http_server_port = kHttpServerPort;
    g_http_server_ready_path = cache_dir + "/node-http-server-ready.json";
    g_http_server_error_path = cache_dir + "/node-http-server-error.txt";
    unlink(g_http_server_ready_path.c_str());
    unlink(g_http_server_error_path.c_str());
  }

  std::string startup_detail;
  if (!EnsureNodeProcessInitializedForHttp(&startup_detail)) {
    g_http_server_starting = false;
    g_http_server_running = false;
    return BuildErrorJson(
        "http-server-start",
        "Failed to initialize Node for HTTP server mode",
        "The app could not initialize libnode before booting the local HTTP server.",
        startup_detail);
  }

  const int port = g_http_server_port.load();
  const std::string ready_path = g_http_server_ready_path;
  const std::string error_path = g_http_server_error_path;
  const std::string script =
      BuildHttpServerScript(port, files_dir, ready_path, error_path);

  std::thread([script]() {
    g_http_server_running = true;
    g_http_server_starting = false;
    RunHttpServerLoop(script);
    g_http_server_running = false;
    g_http_server_starting = false;
    g_http_server_port = 0;
  }).detach();

  const bool is_ready = WaitForFile(ready_path, 5000);
  const bool has_error = access(error_path.c_str(), F_OK) == 0;

  if (!is_ready || has_error) {
    g_http_server_starting = false;
    g_http_server_running = false;
    const std::string detail = has_error
                                   ? ReadFileIfExists(error_path)
                                   : "Timed out waiting for the Node HTTP server to report readiness.";
    return BuildErrorJson(
        "http-server-start",
        "Failed to start the Node HTTP server",
        "The background Node runtime did not become ready for incoming HTTP requests.",
        detail.empty() ? "Unknown HTTP server startup failure." : detail);
  }

  return BuildActionJson(
      "http-server-start",
      "HTTP server is live",
      "A background Node HTTP server is listening inside the app process.",
      {
          {"State", "running"},
          {"Endpoint", "http://127.0.0.1:" + std::to_string(port) + "/"},
          {"Request route", "/"},
          {"Stop route", "/shutdown"},
      });
}

std::string HttpGet(const std::string& host, int port, const std::string& path) {
  const int sock = socket(AF_INET, SOCK_STREAM, 0);
  if (sock < 0) return {};

  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_port = htons(static_cast<uint16_t>(port));
  inet_pton(AF_INET, host.c_str(), &addr.sin_addr);

  if (connect(sock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
    close(sock);
    return {};
  }

  std::ostringstream request;
  request << "GET " << path << " HTTP/1.1\r\n"
          << "Host: " << host << ":" << port << "\r\n"
          << "Connection: close\r\n\r\n";
  const std::string wire = request.str();
  send(sock, wire.c_str(), wire.size(), 0);

  std::string response;
  char buffer[4096];
  ssize_t count = 0;
  while ((count = recv(sock, buffer, sizeof(buffer), 0)) > 0) {
    response.append(buffer, static_cast<size_t>(count));
  }
  close(sock);
  return response;
}

std::string RequestHttpServer() {
  const int port = g_http_server_port.load();
  if (!g_http_server_running.load() || port == 0) {
    return BuildActionJson(
        "http-server-request",
        "HTTP server is offline",
        "Start the Node HTTP server before sending a request.",
        {
            {"State", "stopped"},
            {"Endpoint", "http://127.0.0.1:" + std::to_string(kHttpServerPort) + "/"},
        },
        "error");
  }

  const std::string raw = HttpGet("127.0.0.1", port, "/");
  if (raw.empty()) {
    return BuildErrorJson(
        "http-server-request",
        "Failed to reach the Node HTTP server",
        "The app could not read an HTTP response from the embedded Node server.",
        "connect/read to 127.0.0.1:" + std::to_string(port) + " returned no data.");
  }

  const size_t header_end = raw.find("\r\n\r\n");
  const std::string headers = header_end == std::string::npos ? raw : raw.substr(0, header_end);
  const std::string body =
      header_end == std::string::npos ? std::string() : raw.substr(header_end + 4);
  const std::string status_line =
      headers.substr(0, headers.find("\r\n") == std::string::npos ? headers.size() : headers.find("\r\n"));

  return BuildActionJson(
      "http-server-request",
      "HTTP request completed",
      "The app sent a localhost request and received a live response from Node.",
      {
          {"Status", status_line},
          {"Endpoint", "http://127.0.0.1:" + std::to_string(port) + "/"},
          {"Body bytes", std::to_string(body.size())},
          {"Response preview", body.substr(0, 220)},
      });
}

std::string StopHttpServer() {
  const int port = g_http_server_port.load();
  if (!g_http_server_running.load() || port == 0) {
    return BuildActionJson(
        "http-server-stop",
        "HTTP server already stopped",
        "There is no running Node HTTP server to shut down.",
        {
            {"State", "stopped"},
            {"Endpoint", "http://127.0.0.1:" + std::to_string(kHttpServerPort) + "/"},
        });
  }

  const std::string raw = HttpGet("127.0.0.1", port, "/shutdown");
  const bool got_reply = !raw.empty();
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::milliseconds(2500);
  while (g_http_server_running.load() &&
         std::chrono::steady_clock::now() < deadline) {
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }

  return BuildActionJson(
      "http-server-stop",
      "HTTP server stopped",
      "The embedded Node HTTP server has been asked to close its listener.",
      {
          {"State", g_http_server_running.load() ? "stopping" : "stopped"},
          {"Shutdown reply", got_reply ? "received" : "none"},
          {"Endpoint", "http://127.0.0.1:" + std::to_string(port) + "/shutdown"},
      });
}

bool EnsureNodeProcessInitialized(std::string* detail) {
  if (g_process_initialized) return true;
  if (g_process_failed) {
    *detail = g_process_error;
    return false;
  }

  std::vector<std::string> init_args = {
      "nodeverify",
      "--disable-wasm-trap-handler",
      "--jitless",
  };

  std::shared_ptr<node::InitializationResult> result = node::InitializeOncePerProcess(
      init_args,
      {
          node::ProcessInitializationFlags::kNoInitializeV8,
          node::ProcessInitializationFlags::kNoInitializeNodeV8Platform,
          node::ProcessInitializationFlags::kDisableNodeOptionsEnv,
          node::ProcessInitializationFlags::kNoInitializeCppgc,
      });

  std::ostringstream errors;
  for (const std::string& error : result->errors()) {
    if (!errors.str().empty()) errors << " | ";
    errors << error;
  }
  if (!errors.str().empty()) {
    g_process_failed = true;
    g_process_error = errors.str();
    *detail = g_process_error;
    return false;
  }

  if (result->early_return() != 0) {
    g_process_failed = true;
    g_process_error = "InitializeOncePerProcess requested early return, exitCode=" +
                      std::to_string(result->exit_code());
    *detail = g_process_error;
    return false;
  }

  g_platform = MultiIsolatePlatform::Create(4);
  V8::InitializePlatform(g_platform.get());
  cppgc::InitializeProcess(g_platform->GetPageAllocator());
  V8::Initialize();

  g_exec_args = {
      "--disable-wasm-trap-handler",
      "--jitless",
  };

  g_process_initialized = true;
  __android_log_print(ANDROID_LOG_INFO, kTag, "Initialized Node embedder process state");
  return true;
}

std::string RunEmbeddedScript(const std::string& mode,
                              const std::string& script,
                              const std::string& files_dir,
                              const std::string& cache_dir) {
  const std::string stdout_path = cache_dir + "/node-command-output.json";

  setenv("HOME", files_dir.c_str(), 1);
  setenv("TMPDIR", cache_dir.c_str(), 1);
  setenv("TMP", cache_dir.c_str(), 1);
  setenv("TEMP", cache_dir.c_str(), 1);

  const int output_fd =
      open(stdout_path.c_str(), O_CREAT | O_WRONLY | O_TRUNC, 0644);
  if (output_fd < 0) {
    return BuildErrorJson(
        mode,
        "Failed to prepare Node output capture",
        "The app could not create a writable file for the Node runtime output.",
        "open(" + stdout_path + ") failed before creating the Node environment.");
  }

  const int saved_stdout = dup(STDOUT_FILENO);
  const int saved_stderr = dup(STDERR_FILENO);
  dup2(output_fd, STDOUT_FILENO);
  dup2(output_fd, STDERR_FILENO);
  close(output_fd);

  std::vector<std::string> args = {
      "nodeverify",
      node::GetAnonymousMainPath(),
  };
  std::vector<std::string> errors;

  std::string payload;
  int exit_code = 1;

  {
    std::unique_ptr<CommonEnvironmentSetup> setup =
        CommonEnvironmentSetup::Create(g_platform.get(), &errors, args, g_exec_args);

    if (setup) {
      Isolate* isolate = setup->isolate();
      Environment* env = setup->env();

      Locker locker(isolate);
      Isolate::Scope isolate_scope(isolate);
      HandleScope handle_scope(isolate);
      Context::Scope context_scope(setup->context());

      node::SetProcessExitHandler(env, [](Environment* environment, int) {
        node::Stop(environment);
      });

      MaybeLocal<Value> loadenv_ret = node::LoadEnvironment(env, script);
      if (!loadenv_ret.IsEmpty()) {
        exit_code = node::SpinEventLoop(env).FromMaybe(1);
      }

      node::Stop(env);
    } else {
      std::ostringstream err;
      for (const std::string& part : errors) {
        if (!err.str().empty()) err << " | ";
        err << part;
      }
      payload = BuildErrorJson(
          mode,
          "Failed to create the embedded Node environment",
          "The app initialized libnode, but environment creation failed before the script could run.",
          err.str().empty() ? "CommonEnvironmentSetup::Create() returned null." : err.str());
    }
  }

  fflush(stdout);
  fflush(stderr);
  if (saved_stdout >= 0) {
    dup2(saved_stdout, STDOUT_FILENO);
    close(saved_stdout);
  }
  if (saved_stderr >= 0) {
    dup2(saved_stderr, STDERR_FILENO);
    close(saved_stderr);
  }

  if (payload.empty()) {
    payload = Trim(ReadFileIfExists(stdout_path));
  }

  if (payload.empty()) {
    payload = BuildErrorJson(
        mode,
        "Node finished without a structured payload",
        "The embedded environment returned, but no JSON payload was captured from stdout.",
        "exitCode=" + std::to_string(exit_code));
  }

  return payload;
}

std::string RunNodeCommandImpl(const std::string& mode,
                               const std::string& payload_json,
                               const std::string& files_dir,
                               const std::string& cache_dir) {
  if (mode == "http-server-start") {
    return StartHttpServer(files_dir, cache_dir);
  }
  if (mode == "http-server-request") {
    return RequestHttpServer();
  }
  if (mode == "http-server-stop") {
    return StopHttpServer();
  }

  std::lock_guard<std::mutex> lock(g_node_mutex);

  std::string startup_detail;
  if (!EnsureNodeProcessInitialized(&startup_detail)) {
    return BuildErrorJson(
        mode,
        "Failed to initialize Node embedder state",
        "The app could not initialize the per-process V8/Node runtime required for embedding.",
        startup_detail);
  }

  const std::string proof_path = files_dir + "/node-proof.txt";
  const std::string script = mode == "report"
                                 ? BuildReportScript(files_dir, proof_path)
                                 : BuildActionScript(mode, payload_json, files_dir);
  return RunEmbeddedScript(mode, script, files_dir, cache_dir);
}

}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_viocha_nodeverify_MainActivity_runNodeCommand(
    JNIEnv* env, jclass, jstring mode, jstring payload, jstring files_dir,
    jstring cache_dir) {
  const char* mode_chars = env->GetStringUTFChars(mode, nullptr);
  const char* payload_chars = env->GetStringUTFChars(payload, nullptr);
  const char* files_dir_chars = env->GetStringUTFChars(files_dir, nullptr);
  const char* cache_dir_chars = env->GetStringUTFChars(cache_dir, nullptr);

  std::string result = RunNodeCommandImpl(
      mode_chars == nullptr ? "report" : mode_chars,
      payload_chars == nullptr ? "{}" : payload_chars,
      files_dir_chars == nullptr ? "" : files_dir_chars,
      cache_dir_chars == nullptr ? "" : cache_dir_chars);

  if (mode_chars != nullptr) {
    env->ReleaseStringUTFChars(mode, mode_chars);
  }
  if (payload_chars != nullptr) {
    env->ReleaseStringUTFChars(payload, payload_chars);
  }
  if (files_dir_chars != nullptr) {
    env->ReleaseStringUTFChars(files_dir, files_dir_chars);
  }
  if (cache_dir_chars != nullptr) {
    env->ReleaseStringUTFChars(cache_dir, cache_dir_chars);
  }

  return env->NewStringUTF(result.c_str());
}
