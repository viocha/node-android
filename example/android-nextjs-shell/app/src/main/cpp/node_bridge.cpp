#include <arpa/inet.h>
#include <android/log.h>
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

constexpr const char* kTag = "NextShell";
constexpr const char* kPublicOrigin = "http://localhost/";

std::mutex g_node_mutex;
bool g_process_initialized = false;
bool g_process_failed = false;
std::string g_process_error;
std::unique_ptr<MultiIsolatePlatform> g_platform;
std::vector<std::string> g_exec_args;

std::mutex g_next_mutex;
std::atomic<bool> g_next_server_running{false};
std::atomic<bool> g_next_server_starting{false};
std::atomic<int> g_next_server_port{0};
std::atomic<int> g_next_proxy_port{0};
std::string g_next_error_path;

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

std::string BuildRuntimeJson(const std::string& status,
                             const std::string& url,
                             const std::string& detail,
                             const std::string& proxy_url = "") {
  std::ostringstream out;
  out << "{"
      << "\"status\":\"" << EscapeJsonString(status) << "\","
      << "\"url\":\"" << EscapeJsonString(url) << "\","
      << "\"detail\":\"" << EscapeJsonString(detail) << "\","
      << "\"proxy_url\":\"" << EscapeJsonString(proxy_url) << "\""
      << "}";
  return out.str();
}

std::string BuildLoopbackUrl(int port) {
  if (port <= 0) return {};
  return std::string("http://127.0.0.1:") + std::to_string(port) + "/";
}

std::string BuildProxyRule(int port) {
  if (port <= 0) return {};
  return std::string("http://127.0.0.1:") + std::to_string(port);
}

bool EnsureNodeProcessInitialized(std::string* detail) {
  if (g_process_initialized) return true;
  if (g_process_failed) {
    *detail = g_process_error;
    return false;
  }

  std::vector<std::string> init_args = {
      "nextshell",
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

std::string HttpGet(const std::string& host,
                    int port,
                    const std::string& path,
                    const std::string& host_header = "") {
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
          << "Host: " << (host_header.empty() ? host + ":" + std::to_string(port) : host_header) << "\r\n"
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

int ReserveLoopbackPort() {
  const int sock = socket(AF_INET, SOCK_STREAM, 0);
  if (sock < 0) return 0;

  int reuse = 1;
  setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_port = htons(0);
  inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

  if (bind(sock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
    close(sock);
    return 0;
  }

  socklen_t len = sizeof(addr);
  if (getsockname(sock, reinterpret_cast<sockaddr*>(&addr), &len) != 0) {
    close(sock);
    return 0;
  }

  const int port = ntohs(addr.sin_port);
  close(sock);
  return port;
}

bool HealthcheckReady(int port) {
  if (port <= 0) return false;
  const std::string raw = HttpGet("127.0.0.1", port, "/api/health");
  return raw.find("200") != std::string::npos && raw.find("\"ok\":true") != std::string::npos;
}

bool ProxyHealthcheckReady(int proxy_port) {
  if (proxy_port <= 0) return false;
  const std::string raw = HttpGet("127.0.0.1", proxy_port, "/api/health", "localhost");
  return raw.find("200") != std::string::npos && raw.find("\"ok\":true") != std::string::npos;
}

std::string BuildLaunchScript(const std::string& app_dir,
                              const std::string& error_path,
                              int next_port,
                              int proxy_port) {
  std::string script = R"JS(
const fs = require('node:fs');
const http = require('node:http');
const { createRequire } = require('node:module');
const path = require('node:path');

const appDir = '__APP_DIR__';
const errorPath = '__ERROR_PATH__';
const serverEntry = path.join(appDir, 'server.js');
const appRequire = createRequire(serverEntry);
const nextPort = Number('__NEXT_PORT__');
const proxyPort = Number('__PROXY_PORT__');
const publicHost = 'localhost';

const reportError = (error) => {
  try {
    fs.writeFileSync(errorPath, String(error?.stack || error || 'Unknown startup failure'), 'utf8');
  } catch {}
};

const normalizeRequestPath = (req) => {
  if (!req.url) return '/';
  if (req.url.startsWith('http://') || req.url.startsWith('https://')) {
    const absolute = new URL(req.url);
    if (absolute.hostname !== publicHost) {
      throw new Error(`Unexpected private origin host: ${absolute.hostname}`);
    }
    return `${absolute.pathname}${absolute.search}`;
  }
  return req.url;
};

const proxyServer = http.createServer((req, res) => {
  if ((req.method || 'GET').toUpperCase() === 'CONNECT') {
    res.writeHead(405, { 'content-type': 'text/plain; charset=utf-8' });
    res.end('CONNECT is not supported');
    return;
  }

  let requestPath = '/';
  try {
    requestPath = normalizeRequestPath(req);
  } catch (error) {
    res.writeHead(400, { 'content-type': 'text/plain; charset=utf-8' });
    res.end(String(error?.message || error || 'Bad request'));
    return;
  }

  const headers = { ...req.headers };
  delete headers['proxy-connection'];
  delete headers['connection'];
  delete headers['keep-alive'];
  delete headers['proxy-authenticate'];
  delete headers['proxy-authorization'];
  delete headers['te'];
  delete headers['trailer'];
  delete headers['transfer-encoding'];
  delete headers['upgrade'];
  headers.host = `127.0.0.1:${nextPort}`;
  headers.connection = 'close';

  const upstreamReq = http.request({
    host: '127.0.0.1',
    port: nextPort,
    method: req.method,
    path: requestPath,
    headers,
  }, (upstreamRes) => {
    res.writeHead(
      upstreamRes.statusCode || 502,
      upstreamRes.statusMessage || 'Bad Gateway',
      upstreamRes.headers
    );
    upstreamRes.pipe(res);
  });

  upstreamReq.on('error', (error) => {
    res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' });
    res.end(String(error?.stack || error || 'Proxy request failed'));
  });

  req.pipe(upstreamReq);
});

proxyServer.on('clientError', (error, socket) => {
  try {
    socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n');
  } catch {}
  reportError(error);
});

proxyServer.on('error', reportError);

process.chdir(appDir);
process.env.NODE_ENV = 'production';
process.env.PORT = '__NEXT_PORT__';
process.env.HOSTNAME = '127.0.0.1';
process.env.NEXT_TELEMETRY_DISABLED = '1';
process.env.__NEXT_DISABLE_MEMORY_WATCHER = '1';
process.argv = ['node', serverEntry];

process.on('uncaughtException', reportError);
process.on('unhandledRejection', reportError);
process.on('exit', () => {
  try {
    proxyServer.close();
  } catch {}
});

try {
  proxyServer.listen(proxyPort, '127.0.0.1');
  appRequire(serverEntry);
} catch (error) {
  reportError(error);
  throw error;
}
)JS";

  ReplaceAll(&script, "__APP_DIR__", EscapeJsString(app_dir));
  ReplaceAll(&script, "__ERROR_PATH__", EscapeJsString(error_path));
  ReplaceAll(&script, "__NEXT_PORT__", std::to_string(next_port));
  ReplaceAll(&script, "__PROXY_PORT__", std::to_string(proxy_port));
  return script;
}

bool RunNextServerLoop(const std::string& script,
                       const std::string& app_dir,
                       const std::string& cache_dir) {
  setenv("HOME", app_dir.c_str(), 1);
  setenv("TMPDIR", cache_dir.c_str(), 1);
  setenv("TMP", cache_dir.c_str(), 1);
  setenv("TEMP", cache_dir.c_str(), 1);

  std::vector<std::string> args = {
      "nextshell",
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
    if (!g_next_error_path.empty()) {
      std::ofstream out(g_next_error_path, std::ios::trunc);
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

std::string StartNextServer(const std::string& app_dir,
                            const std::string& cache_dir) {
  const std::string server_js = app_dir + "/server.js";
  if (access(server_js.c_str(), F_OK) != 0) {
    return BuildRuntimeJson(
        "error",
        "",
        "Missing extracted Next.js standalone entrypoint: " + server_js);
  }

  {
    std::lock_guard<std::mutex> lock(g_next_mutex);
    if (g_next_server_running.load()) {
      return BuildRuntimeJson(
          "success",
          kPublicOrigin,
          "Next.js server already running",
          BuildProxyRule(g_next_proxy_port.load()));
    }
    if (g_next_server_starting.load()) {
      return BuildRuntimeJson(
          "starting",
          kPublicOrigin,
          "Next.js server is still starting",
          BuildProxyRule(g_next_proxy_port.load()));
    }

    const int next_port = ReserveLoopbackPort();
    if (next_port <= 0) {
      return BuildRuntimeJson(
          "error",
          "",
          "Failed to reserve a loopback port for the embedded Next.js server");
    }

    const int proxy_port = ReserveLoopbackPort();
    if (proxy_port <= 0) {
      return BuildRuntimeJson(
          "error",
          "",
          "Failed to reserve a loopback port for the embedded private-origin proxy");
    }

    g_next_server_port = next_port;
    g_next_proxy_port = proxy_port;
    g_next_server_starting = true;
    g_next_error_path = cache_dir + "/nextjs-shell-error.txt";
    unlink(g_next_error_path.c_str());
  }

  std::string startup_detail;
  {
    std::lock_guard<std::mutex> lock(g_node_mutex);
    if (!EnsureNodeProcessInitialized(&startup_detail)) {
      g_next_server_starting = false;
      g_next_server_running = false;
      g_next_server_port = 0;
      g_next_proxy_port = 0;
      return BuildRuntimeJson("error", "", startup_detail, "");
    }
  }

  const int next_port = g_next_server_port.load();
  const int proxy_port = g_next_proxy_port.load();
  const std::string script = BuildLaunchScript(app_dir, g_next_error_path, next_port, proxy_port);

  std::thread([script, app_dir, cache_dir]() {
    g_next_server_running = true;
    g_next_server_starting = false;
    RunNextServerLoop(script, app_dir, cache_dir);
    g_next_server_running = false;
    g_next_server_starting = false;
    g_next_server_port = 0;
    g_next_proxy_port = 0;
  }).detach();

  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(12);
  while (std::chrono::steady_clock::now() < deadline) {
    if (access(g_next_error_path.c_str(), F_OK) == 0) {
      const std::string detail = Trim(ReadFileIfExists(g_next_error_path));
      g_next_server_running = false;
      g_next_server_starting = false;
      g_next_server_port = 0;
      g_next_proxy_port = 0;
      return BuildRuntimeJson(
          "error",
          "",
          detail.empty() ? "Next.js server failed before becoming healthy." : detail,
          "");
    }

    if (HealthcheckReady(next_port) && ProxyHealthcheckReady(proxy_port)) {
      __android_log_print(
          ANDROID_LOG_INFO,
          kTag,
          "Embedded Next.js server ready: upstream=%s proxy=%s",
          BuildLoopbackUrl(next_port).c_str(),
          BuildLoopbackUrl(proxy_port).c_str());
      return BuildRuntimeJson(
          "success",
          kPublicOrigin,
          "Next.js server is ready behind the private app origin",
          BuildProxyRule(proxy_port));
    }

    std::this_thread::sleep_for(std::chrono::milliseconds(120));
  }

  g_next_server_running = false;
  g_next_server_starting = false;
  g_next_server_port = 0;
  g_next_proxy_port = 0;
  return BuildRuntimeJson(
      "error",
      "",
      "Timed out waiting for the embedded private-origin proxy to answer /api/health",
      "");
}

}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_viocha_nextshell_MainActivity_startNextServer(
    JNIEnv* env, jclass, jstring app_dir, jstring cache_dir) {
  const char* app_dir_chars = env->GetStringUTFChars(app_dir, nullptr);
  const char* cache_dir_chars = env->GetStringUTFChars(cache_dir, nullptr);

  const std::string result = StartNextServer(
      app_dir_chars == nullptr ? "" : app_dir_chars,
      cache_dir_chars == nullptr ? "" : cache_dir_chars);

  if (app_dir_chars != nullptr) {
    env->ReleaseStringUTFChars(app_dir, app_dir_chars);
  }
  if (cache_dir_chars != nullptr) {
    env->ReleaseStringUTFChars(cache_dir, cache_dir_chars);
  }

  return env->NewStringUTF(result.c_str());
}
