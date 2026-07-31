#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <shellapi.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <mutex>
#include <string>
#include <vector>

#include "green_vpn_runtime_config.h"

#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "ws2_32.lib")

namespace {

constexpr wchar_t kServiceName[] = GREENVPN_RUNTIME_SERVICE_NAME_W;
constexpr char kServiceNameUtf8[] = GREENVPN_RUNTIME_SERVICE_NAME_A;
constexpr wchar_t kTunnelServiceName[] =
    L"WireGuardTunnel$" GREENVPN_RUNTIME_TUNNEL_NAME_W;
constexpr char kTunnelServiceNameUtf8[] =
    "WireGuardTunnel$" GREENVPN_RUNTIME_TUNNEL_NAME_A;
constexpr wchar_t kAmneziaWgTunnelServiceName[] =
    L"AmneziaWGTunnel$" GREENVPN_RUNTIME_TUNNEL_NAME_W;
constexpr char kAmneziaWgTunnelServiceNameUtf8[] =
    "AmneziaWGTunnel$" GREENVPN_RUNTIME_TUNNEL_NAME_A;
constexpr unsigned short kPort = GREENVPN_RUNTIME_LOCAL_SERVICE_PORT;
constexpr wchar_t kProgramDataRoot[] = GREENVPN_RUNTIME_PROGRAM_DATA_ROOT_W;
constexpr wchar_t kBackendLogPath[] =
    GREENVPN_RUNTIME_PROGRAM_DATA_ROOT_W L"\\backend.log";
constexpr char kLocalTokenPath[] =
    GREENVPN_RUNTIME_PROGRAM_DATA_ROOT_A "\\service_token";
constexpr char kLocalTokenHeader[] = "x-greenvpn-local-token";
constexpr char kProtocolPath[] = GREENVPN_RUNTIME_PROGRAM_DATA_ROOT_A "\\"
    GREENVPN_RUNTIME_TUNNEL_NAME_A ".conf.protocol";
constexpr char kHysteriaPidPath[] =
    GREENVPN_RUNTIME_PROGRAM_DATA_ROOT_A "\\hysteria2-client.pid";
constexpr char kHevPidPath[] =
    GREENVPN_RUNTIME_PROGRAM_DATA_ROOT_A "\\hysteria2-hev.pid";
constexpr char kVlessXrayPidPath[] =
    GREENVPN_RUNTIME_PROGRAM_DATA_ROOT_A "\\vless-reality-client.pid";
constexpr char kVlessHevPidPath[] =
    GREENVPN_RUNTIME_PROGRAM_DATA_ROOT_A "\\vless-reality-hev.pid";
constexpr char kNaivePidPath[] =
    GREENVPN_RUNTIME_PROGRAM_DATA_ROOT_A "\\naive-https-client.pid";
constexpr char kNaiveHevPidPath[] =
    GREENVPN_RUNTIME_PROGRAM_DATA_ROOT_A "\\naive-https-hev.pid";
constexpr char kDnsttPidPath[] =
    GREENVPN_RUNTIME_PROGRAM_DATA_ROOT_A "\\dnstt-client.pid";
constexpr char kDnsttHevPidPath[] =
    GREENVPN_RUNTIME_PROGRAM_DATA_ROOT_A "\\dnstt-hev.pid";
constexpr char kRoutingModePath[] =
    GREENVPN_RUNTIME_PROGRAM_DATA_ROOT_A "\\routing_mode";
constexpr char kProcessRouterPidPath[] =
    GREENVPN_RUNTIME_PROGRAM_DATA_ROOT_A "\\process-router.pid";
constexpr wchar_t kProcessRouterActivePath[] =
    GREENVPN_RUNTIME_PROGRAM_DATA_ROOT_W L"\\process-router.active";

SERVICE_STATUS_HANDLE g_status_handle = nullptr;
SERVICE_STATUS g_status = {};
HANDLE g_stop_event = nullptr;
HANDLE g_worker_thread = nullptr;
HANDLE g_guard_thread = nullptr;
SOCKET g_listen_socket = INVALID_SOCKET;
std::wstring g_task_script_path;
std::mutex g_task_action_mutex;
constexpr const wchar_t kStandbyProbeCancelPath[] =
    GREENVPN_RUNTIME_PROGRAM_DATA_ROOT_W L"\\standby-probe.cancel";

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) {
    return L"";
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                      static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) {
    return L"";
  }
  std::wstring out(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      out.data(), size);
  return out;
}

std::string WideToUtf8(const std::wstring& text) {
  if (text.empty()) {
    return "";
  }
  const int size = WideCharToMultiByte(CP_UTF8, 0, text.data(),
                                      static_cast<int>(text.size()), nullptr, 0,
                                      nullptr, nullptr);
  if (size <= 0) {
    return "";
  }
  std::string out(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      out.data(), size, nullptr, nullptr);
  return out;
}

std::wstring QuoteArg(const std::wstring& value) {
  std::wstring out = L"\"";
  for (wchar_t ch : value) {
    if (ch == L'"') {
      out += L"\\\"";
    } else {
      out += ch;
    }
  }
  out += L"\"";
  return out;
}

std::wstring GetModuleDirectory() {
  std::vector<wchar_t> buffer(MAX_PATH);
  DWORD len = 0;
  while (true) {
    len = GetModuleFileNameW(nullptr, buffer.data(),
                             static_cast<DWORD>(buffer.size()));
    if (len == 0) {
      return L"";
    }
    if (len < buffer.size() - 1) {
      break;
    }
    buffer.resize(buffer.size() * 2);
  }
  std::wstring path(buffer.data(), len);
  const size_t slash = path.find_last_of(L"\\/");
  if (slash == std::wstring::npos) {
    return L"";
  }
  return path.substr(0, slash);
}

bool FileExists(const std::wstring& path) {
  const DWORD attrs = GetFileAttributesW(path.c_str());
  return attrs != INVALID_FILE_ATTRIBUTES &&
         (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

std::wstring DefaultTaskScriptPath() {
  const std::wstring dir = GetModuleDirectory();
  if (dir.empty()) {
    return L"";
  }
  return dir + L"\\tools\\greenvpn_vpn_task.ps1";
}

void EnsureProgramDataDirectory() {
  CreateDirectoryW(kProgramDataRoot, nullptr);
}

void AppendLog(const std::wstring& message) {
  EnsureProgramDataDirectory();
  SYSTEMTIME st = {};
  GetLocalTime(&st);

  wchar_t prefix[96] = {};
  swprintf_s(prefix, L"[%04u-%02u-%02uT%02u:%02u:%02u.%03u] service ",
             st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
             st.wMilliseconds);

  std::string line = WideToUtf8(std::wstring(prefix) + message + L"\r\n");
  HANDLE file = CreateFileW(kBackendLogPath,
                            FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                            nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }
  DWORD written = 0;
  WriteFile(file, line.data(), static_cast<DWORD>(line.size()), &written,
            nullptr);
  CloseHandle(file);
}

void ReportServiceStatus(DWORD current_state, DWORD win32_exit_code,
                         DWORD wait_hint) {
  if (g_status_handle == nullptr) {
    return;
  }

  g_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  g_status.dwCurrentState = current_state;
  g_status.dwWin32ExitCode = win32_exit_code;
  g_status.dwWaitHint = wait_hint;
  g_status.dwControlsAccepted =
      (current_state == SERVICE_START_PENDING) ? 0 : SERVICE_ACCEPT_STOP;

  static DWORD checkpoint = 1;
  if (current_state == SERVICE_RUNNING || current_state == SERVICE_STOPPED) {
    g_status.dwCheckPoint = 0;
  } else {
    g_status.dwCheckPoint = checkpoint++;
  }

  SetServiceStatus(g_status_handle, &g_status);
}

std::string JsonEscape(const std::string& text) {
  std::string out;
  out.reserve(text.size() + 8);
  for (char ch : text) {
    switch (ch) {
      case '\\':
        out += "\\\\";
        break;
      case '"':
        out += "\\\"";
        break;
      case '\b':
        out += "\\b";
        break;
      case '\f':
        out += "\\f";
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
        if (static_cast<unsigned char>(ch) < 0x20) {
          char buf[7] = {};
          sprintf_s(buf, "\\u%04x", static_cast<unsigned char>(ch));
          out += buf;
        } else {
          out += ch;
        }
        break;
    }
  }
  return out;
}

void SendHttp(SOCKET client, int status_code, const std::string& status_text,
              const std::string& body) {
  std::string response = "HTTP/1.1 " + std::to_string(status_code) + " " +
                         status_text + "\r\n";
  response += "Content-Type: application/json; charset=utf-8\r\n";
  response += "Cache-Control: no-store\r\n";
  response += "Connection: close\r\n";
  response += "Content-Length: " + std::to_string(body.size()) + "\r\n\r\n";
  response += body;

  const char* data = response.data();
  int remaining = static_cast<int>(response.size());
  while (remaining > 0) {
    const int sent = send(client, data, remaining, 0);
    if (sent <= 0) {
      break;
    }
    data += sent;
    remaining -= sent;
  }
}

std::string LowerAscii(std::string text) {
  std::transform(text.begin(), text.end(), text.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return text;
}

std::string TrimAscii(std::string text) {
  const auto is_space = [](unsigned char ch) {
    return std::isspace(ch) != 0;
  };
  while (!text.empty() && is_space(static_cast<unsigned char>(text.front()))) {
    text.erase(text.begin());
  }
  while (!text.empty() && is_space(static_cast<unsigned char>(text.back()))) {
    text.pop_back();
  }
  return text;
}

std::string ReadLocalServiceToken() {
  std::ifstream file(kLocalTokenPath, std::ios::binary);
  if (!file) {
    return "";
  }
  std::string token((std::istreambuf_iterator<char>(file)),
                    std::istreambuf_iterator<char>());
  return TrimAscii(token);
}

std::string HeaderValue(const std::string& request,
                        const std::string& wanted_lower_name) {
  size_t pos = request.find("\r\n");
  if (pos == std::string::npos) {
    return "";
  }
  pos += 2;

  while (pos < request.size()) {
    const size_t line_end = request.find("\r\n", pos);
    const size_t end = line_end == std::string::npos ? request.size() : line_end;
    const std::string line = request.substr(pos, end - pos);
    if (line.empty()) {
      break;
    }

    const size_t colon = line.find(':');
    if (colon != std::string::npos) {
      const std::string name =
          LowerAscii(TrimAscii(line.substr(0, colon)));
      if (name == wanted_lower_name) {
        return TrimAscii(line.substr(colon + 1));
      }
    }

    if (line_end == std::string::npos) {
      break;
    }
    pos = line_end + 2;
  }

  return "";
}

bool FixedTimeEquals(const std::string& a, const std::string& b) {
  if (a.empty() || b.empty()) {
    return false;
  }

  unsigned char diff = static_cast<unsigned char>(a.size() ^ b.size());
  const size_t max_len = std::max(a.size(), b.size());
  for (size_t i = 0; i < max_len; ++i) {
    const unsigned char ca =
        i < a.size() ? static_cast<unsigned char>(a[i]) : 0;
    const unsigned char cb =
        i < b.size() ? static_cast<unsigned char>(b[i]) : 0;
    diff |= static_cast<unsigned char>(ca ^ cb);
  }
  return diff == 0;
}

enum class LocalAuthResult { kOk, kTokenMissing, kDenied };

LocalAuthResult AuthorizeLocalRequest(const std::string& request) {
  const std::string expected = ReadLocalServiceToken();
  if (expected.empty()) {
    AppendLog(L"protected request denied: local service token missing");
    return LocalAuthResult::kTokenMissing;
  }

  const std::string provided = HeaderValue(request, kLocalTokenHeader);
  if (!FixedTimeEquals(provided, expected)) {
    AppendLog(L"protected request denied: local service token mismatch");
    return LocalAuthResult::kDenied;
  }
  return LocalAuthResult::kOk;
}

bool ParseRequestLine(const std::string& first_line, std::string* method,
                      std::string* path) {
  const size_t first_space = first_line.find(' ');
  if (first_space == std::string::npos) {
    return false;
  }
  const size_t second_space = first_line.find(' ', first_space + 1);
  if (second_space == std::string::npos) {
    return false;
  }

  *method = LowerAscii(first_line.substr(0, first_space));
  std::string target =
      first_line.substr(first_space + 1, second_space - first_space - 1);
  const size_t query = target.find('?');
  if (query != std::string::npos) {
    target = target.substr(0, query);
  }
  *path = LowerAscii(target);
  return true;
}

bool RequireLocalToken(SOCKET client, const std::string& request) {
  const LocalAuthResult auth = AuthorizeLocalRequest(request);
  if (auth == LocalAuthResult::kOk) {
    return true;
  }
  if (auth == LocalAuthResult::kTokenMissing) {
    SendHttp(client, 503, "Service Unavailable",
             "{\"ok\":false,\"message\":\"local service token missing; "
             "reinstall Green VPN\"}");
  } else {
    SendHttp(client, 401, "Unauthorized",
             "{\"ok\":false,\"message\":\"unauthorized local request\"}");
  }
  return false;
}

std::wstring GetPowerShellPath() {
  wchar_t windows_dir[MAX_PATH] = {};
  if (GetWindowsDirectoryW(windows_dir, MAX_PATH) > 0) {
    std::wstring path =
        std::wstring(windows_dir) +
        L"\\System32\\WindowsPowerShell\\v1.0\\powershell.exe";
    if (FileExists(path)) {
      return path;
    }
  }
  return L"powershell.exe";
}

int RunTaskAction(const wchar_t* action, DWORD timeout_ms,
                  bool clear_standby_cancel = false) {
  const std::lock_guard<std::mutex> lock(g_task_action_mutex);
  if (clear_standby_cancel &&
      !DeleteFileW(kStandbyProbeCancelPath) &&
      GetLastError() != ERROR_FILE_NOT_FOUND) {
    AppendLog(L"standby probe cancellation reset failed err=" +
              std::to_wstring(GetLastError()));
    return 4;
  }
  if (g_task_script_path.empty() || !FileExists(g_task_script_path)) {
    AppendLog(L"task script missing: " + g_task_script_path);
    return 3;
  }

  const std::wstring powershell = GetPowerShellPath();
  std::wstring command = QuoteArg(powershell) +
                         L" -NoProfile -ExecutionPolicy RemoteSigned -File " +
                         QuoteArg(g_task_script_path) +
                         L" -Action " + action;

  STARTUPINFOW si = {};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESHOWWINDOW;
  si.wShowWindow = SW_HIDE;
  PROCESS_INFORMATION pi = {};

  AppendLog(L"running task action " + std::wstring(action));
  BOOL ok = CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE,
                           CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi);
  if (!ok) {
    const DWORD err = GetLastError();
    AppendLog(L"CreateProcess failed err=" + std::to_wstring(err));
    return 1000 + static_cast<int>(err % 1000);
  }

  const DWORD wait_result = WaitForSingleObject(pi.hProcess, timeout_ms);
  int exit_code = 124;
  if (wait_result == WAIT_TIMEOUT) {
    AppendLog(L"task action timed out");
    TerminateProcess(pi.hProcess, 124);
  } else {
    DWORD process_exit_code = 1;
    if (GetExitCodeProcess(pi.hProcess, &process_exit_code)) {
      exit_code = static_cast<int>(process_exit_code);
    }
  }

  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  AppendLog(L"task action " + std::wstring(action) +
            L" exit=" + std::to_wstring(exit_code));
  return exit_code;
}

bool RequestStandbyProbeCancellation() {
  HANDLE file = CreateFileW(kStandbyProbeCancelPath, GENERIC_WRITE,
                            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                            nullptr, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_TEMPORARY,
                            nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    AppendLog(L"standby probe cancellation marker failed err=" +
              std::to_wstring(GetLastError()));
    return false;
  }
  CloseHandle(file);
  return true;
}

bool CancelStandbyProbeAndWait() {
  if (!RequestStandbyProbeCancellation()) {
    return false;
  }
  const std::lock_guard<std::mutex> lock(g_task_action_mutex);
  if (!DeleteFileW(kStandbyProbeCancelPath) &&
      GetLastError() != ERROR_FILE_NOT_FOUND) {
    AppendLog(L"standby probe cancellation cleanup failed err=" +
              std::to_wstring(GetLastError()));
    return false;
  }
  return true;
}

std::string QueryServiceState(const wchar_t* service_name) {
  std::string state = "missing";
  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (scm != nullptr) {
    SC_HANDLE svc = OpenServiceW(scm, service_name, SERVICE_QUERY_STATUS);
    if (svc != nullptr) {
      SERVICE_STATUS_PROCESS status = {};
      DWORD needed = 0;
      if (QueryServiceStatusEx(svc, SC_STATUS_PROCESS_INFO,
                               reinterpret_cast<LPBYTE>(&status),
                               sizeof(status), &needed)) {
        switch (status.dwCurrentState) {
          case SERVICE_RUNNING:
            state = "running";
            break;
          case SERVICE_START_PENDING:
            state = "start_pending";
            break;
          case SERVICE_STOP_PENDING:
            state = "stop_pending";
            break;
          case SERVICE_STOPPED:
            state = "stopped";
            break;
          default:
            state = "other";
            break;
        }
      } else {
        state = "query_failed";
      }
      CloseServiceHandle(svc);
    }
    CloseServiceHandle(scm);
  }

  return state;
}

std::string ReadTrimmedAsciiFile(const char* path) {
  std::ifstream input(path, std::ios::binary);
  if (!input) {
    return "";
  }
  std::string value((std::istreambuf_iterator<char>(input)),
                    std::istreambuf_iterator<char>());
  while (!value.empty() &&
         std::isspace(static_cast<unsigned char>(value.back()))) {
    value.pop_back();
  }
  size_t start = 0;
  while (start < value.size() &&
         std::isspace(static_cast<unsigned char>(value[start]))) {
    ++start;
  }
  value = value.substr(start);
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
  return value;
}

std::string QueryPidFileProcessState(const char* pid_path,
                                     const std::wstring& expected_path) {
  const std::string pid_text = ReadTrimmedAsciiFile(pid_path);
  if (pid_text.empty() ||
      !std::all_of(pid_text.begin(), pid_text.end(),
                   [](unsigned char ch) { return std::isdigit(ch) != 0; })) {
    return "missing";
  }
  unsigned long parsed = 0;
  try {
    parsed = std::stoul(pid_text);
  } catch (...) {
    return "invalid";
  }
  if (parsed == 0 || parsed > MAXDWORD) {
    return "invalid";
  }
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE,
                               FALSE, static_cast<DWORD>(parsed));
  if (process == nullptr) {
    return "stopped";
  }
  DWORD exit_code = 0;
  const bool running = GetExitCodeProcess(process, &exit_code) != FALSE &&
                       exit_code == STILL_ACTIVE;
  std::vector<wchar_t> image_path(32768);
  DWORD image_size = static_cast<DWORD>(image_path.size());
  const bool path_matches =
      QueryFullProcessImageNameW(process, 0, image_path.data(), &image_size) !=
          FALSE &&
      _wcsicmp(std::wstring(image_path.data(), image_size).c_str(),
               expected_path.c_str()) == 0;
  CloseHandle(process);
  return running && path_matches ? "running" : "stopped";
}

std::string QueryTunnelStatusJson() {
  const std::string wireguard_state = QueryServiceState(kTunnelServiceName);
  const std::string amneziawg_state =
      QueryServiceState(kAmneziaWgTunnelServiceName);
  const std::string managed_protocol = ReadTrimmedAsciiFile(kProtocolPath);
  const std::wstring module_dir = GetModuleDirectory();
  const std::string hysteria_state = QueryPidFileProcessState(
      kHysteriaPidPath,
      module_dir + L"\\tools\\hysteria2\\hysteria-windows-amd64.exe");
  const std::string hev_state = QueryPidFileProcessState(
      kHevPidPath,
      module_dir + L"\\tools\\hysteria2\\hev-socks5-tunnel.exe");
  const std::string vless_xray_state = QueryPidFileProcessState(
      kVlessXrayPidPath,
      module_dir + L"\\tools\\vless-reality\\xray.exe");
  const std::string vless_hev_state = QueryPidFileProcessState(
      kVlessHevPidPath,
      module_dir + L"\\tools\\vless-reality\\hev-socks5-tunnel.exe");
  const std::string naive_state = QueryPidFileProcessState(
      kNaivePidPath, module_dir + L"\\tools\\naive-https\\naive.exe");
  const std::string naive_hev_state = QueryPidFileProcessState(
      kNaiveHevPidPath,
      module_dir + L"\\tools\\naive-https\\hev-socks5-tunnel.exe");
  const std::string dnstt_state = QueryPidFileProcessState(
      kDnsttPidPath,
      module_dir + L"\\tools\\dnstt\\dnstt-client-windows-amd64.exe");
  const std::string dnstt_hev_state = QueryPidFileProcessState(
      kDnsttHevPidPath,
      module_dir + L"\\tools\\dnstt\\hev-socks5-tunnel.exe");
  const std::string requested_routing_mode =
      ReadTrimmedAsciiFile(kRoutingModePath) == "applications" ? "applications"
                                                               : "full";
  const bool process_router_active = FileExists(kProcessRouterActivePath);
  const std::string routing_mode =
      process_router_active ? "applications" : requested_routing_mode;
  const std::string process_router_state = QueryPidFileProcessState(
      kProcessRouterPidPath,
      module_dir + L"\\tools\\process-router\\ProxyBridge_CLI.exe");

  std::string selected_service = kTunnelServiceNameUtf8;
  std::string selected_state = wireguard_state;
  std::string selected_protocol = "wireguard_udp";
  if (managed_protocol == "hysteria2") {
    selected_service = "GreenVPNHysteria2Preview";
    selected_state =
        hysteria_state == "running" && hev_state == "running" ? "running"
                                                               : "stopped";
    selected_protocol = "hysteria2";
  } else if (managed_protocol == "vless_reality") {
    selected_service = "GreenVPNVlessRealityPreview";
    selected_state =
        vless_xray_state == "running" && vless_hev_state == "running"
            ? "running"
            : "stopped";
    selected_protocol = "vless_reality";
  } else if (managed_protocol == "naive_https") {
    selected_service = "GreenVPNNaiveHttpsPreview";
    selected_state =
        naive_state == "running" && naive_hev_state == "running" ? "running"
                                                                  : "stopped";
    selected_protocol = "naive_https";
  } else if (managed_protocol == "dnstt") {
    selected_service = "GreenVPNDnsttPreview";
    selected_state =
        dnstt_state == "running" && dnstt_hev_state == "running" ? "running"
                                                                  : "stopped";
    selected_protocol = "dnstt";
  } else {
    const bool awg_selected = amneziawg_state == "running" ||
                              (amneziawg_state != "missing" &&
                               wireguard_state == "missing");
    if (awg_selected) {
      selected_service = kAmneziaWgTunnelServiceNameUtf8;
      selected_state = amneziawg_state;
      selected_protocol = "amneziawg";
    }
  }

  return std::string("{\"ok\":true,\"service\":\"") + kServiceNameUtf8 +
         "\",\"tunnelService\":\"" + selected_service + "\"," +
         "\"tunnelState\":\"" + selected_state + "\"," +
         "\"protocol\":\"" + selected_protocol + "\"," +
         "\"wireGuardState\":\"" + wireguard_state + "\"," +
         "\"amneziaWgState\":\"" + amneziawg_state + "\"," +
         "\"hysteriaClientState\":\"" + hysteria_state + "\"," +
         "\"hysteriaTunState\":\"" + hev_state + "\"," +
         "\"vlessClientState\":\"" + vless_xray_state + "\"," +
         "\"vlessTunState\":\"" + vless_hev_state + "\"," +
         "\"naiveClientState\":\"" + naive_state + "\"," +
         "\"naiveTunState\":\"" + naive_hev_state + "\"," +
         "\"dnsttClientState\":\"" + dnstt_state + "\"," +
         "\"dnsttTunState\":\"" + dnstt_hev_state + "\"," +
         "\"routingMode\":\"" + routing_mode + "\"," +
         "\"processRouterState\":\"" + process_router_state + "\"}";
}

std::string TaskResultJson(bool ok, int exit_code, const std::string& message) {
  return std::string("{\"ok\":") + (ok ? "true" : "false") +
         ",\"exitCode\":" + std::to_string(exit_code) + ",\"message\":\"" +
         JsonEscape(message) + "\"}";
}

void HandleRequest(SOCKET client, const std::string& request) {
  const size_t line_end = request.find("\r\n");
  const std::string first_line =
      line_end == std::string::npos ? request : request.substr(0, line_end);
  std::string method;
  std::string path;
  if (!ParseRequestLine(first_line, &method, &path)) {
    SendHttp(client, 400, "Bad Request",
             "{\"ok\":false,\"message\":\"bad request\"}");
    return;
  }

  if (method == "get" && path == "/ping") {
    SendHttp(client, 200, "OK", std::string("{\"ok\":true,\"service\":\"") +
             kServiceNameUtf8 + "\",\"authRequired\":true}");
    return;
  }

  if (method == "get" && path == "/status") {
    if (!RequireLocalToken(client, request)) {
      return;
    }
    SendHttp(client, 200, "OK", QueryTunnelStatusJson());
    return;
  }

  if (path == "/connect" && method != "post") {
    SendHttp(client, 405, "Method Not Allowed",
             "{\"ok\":false,\"message\":\"connect requires POST\"}");
    return;
  }

  if (method == "post" && path == "/connect") {
    if (!RequireLocalToken(client, request)) {
      return;
    }
    CancelStandbyProbeAndWait();
    const int exit_code = RunTaskAction(L"Connect", 120000);
    if (exit_code == 0) {
      SendHttp(client, 200, "OK",
               TaskResultJson(true, exit_code, "connect task accepted"));
    } else if (exit_code == 2) {
      SendHttp(client, 409, "Conflict",
               TaskResultJson(false, exit_code,
                              "competing VPN could not be stopped"));
    } else {
      SendHttp(client, 500, "Internal Server Error",
               TaskResultJson(false, exit_code, "connect task failed"));
    }
    return;
  }

  if (path == "/disconnect" && method != "post") {
    SendHttp(client, 405, "Method Not Allowed",
             "{\"ok\":false,\"message\":\"disconnect requires POST\"}");
    return;
  }

  if (method == "post" && path == "/disconnect") {
    if (!RequireLocalToken(client, request)) {
      return;
    }
    CancelStandbyProbeAndWait();
    const int exit_code = RunTaskAction(L"Disconnect", 120000);
    if (exit_code == 0) {
      SendHttp(client, 200, "OK",
               TaskResultJson(true, exit_code, "disconnect task accepted"));
    } else {
      SendHttp(client, 500, "Internal Server Error",
               TaskResultJson(false, exit_code, "disconnect task failed"));
    }
    return;
  }

  if (path == "/standby/cancel" && method != "post") {
    SendHttp(client, 405, "Method Not Allowed",
             "{\"ok\":false,\"message\":\"standby cancel requires POST\"}");
    return;
  }

  if (method == "post" && path == "/standby/cancel") {
    if (!RequireLocalToken(client, request)) {
      return;
    }
    const bool ok = CancelStandbyProbeAndWait();
    SendHttp(client, ok ? 200 : 500,
             ok ? "OK" : "Internal Server Error",
             ok ? "{\"ok\":true,\"message\":\"standby probe cancellation requested\"}"
                : "{\"ok\":false,\"message\":\"standby probe cancellation failed\"}");
    return;
  }

  if (path == "/standby/probe" && method != "post") {
    SendHttp(client, 405, "Method Not Allowed",
             "{\"ok\":false,\"message\":\"standby probe requires POST\"}");
    return;
  }

  if (method == "post" && path == "/standby/probe") {
    if (!RequireLocalToken(client, request)) {
      return;
    }
    const int exit_code = RunTaskAction(L"ProbeStandby", 60000, true);
    if (exit_code == 0) {
      SendHttp(client, 200, "OK",
               TaskResultJson(true, exit_code, "standby probe completed"));
    } else {
      SendHttp(client, 409, "Conflict",
               TaskResultJson(false, exit_code, "standby probe failed or was cancelled"));
    }
    return;
  }

  SendHttp(client, 404, "Not Found",
           "{\"ok\":false,\"message\":\"not found\"}");
}

DWORD WINAPI HttpWorkerThread(LPVOID) {
  WSADATA wsa = {};
  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
    AppendLog(L"WSAStartup failed");
    return 1;
  }

  SOCKET listen_socket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (listen_socket == INVALID_SOCKET) {
    AppendLog(L"socket failed");
    WSACleanup();
    return 1;
  }

  BOOL reuse = TRUE;
  setsockopt(listen_socket, SOL_SOCKET, SO_REUSEADDR,
             reinterpret_cast<const char*>(&reuse), sizeof(reuse));

  sockaddr_in addr = {};
  addr.sin_family = AF_INET;
  addr.sin_port = htons(kPort);
  InetPtonW(AF_INET, L"127.0.0.1", &addr.sin_addr);

  if (bind(listen_socket, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) ==
      SOCKET_ERROR) {
    AppendLog(L"bind failed on 127.0.0.1:" + std::to_wstring(kPort));
    closesocket(listen_socket);
    WSACleanup();
    return 1;
  }

  if (listen(listen_socket, SOMAXCONN) == SOCKET_ERROR) {
    AppendLog(L"listen failed");
    closesocket(listen_socket);
    WSACleanup();
    return 1;
  }

  g_listen_socket = listen_socket;
  AppendLog(L"listening on 127.0.0.1:" + std::to_wstring(kPort) +
            L" task=" + g_task_script_path);

  while (WaitForSingleObject(g_stop_event, 0) == WAIT_TIMEOUT) {
    SOCKET client = accept(listen_socket, nullptr, nullptr);
    if (client == INVALID_SOCKET) {
      if (WaitForSingleObject(g_stop_event, 0) != WAIT_TIMEOUT) {
        break;
      }
      Sleep(100);
      continue;
    }

    char buffer[4096] = {};
    const int received = recv(client, buffer, sizeof(buffer), 0);
    if (received > 0) {
      HandleRequest(client, std::string(buffer, static_cast<size_t>(received)));
    }
    shutdown(client, SD_BOTH);
    closesocket(client);
  }

  g_listen_socket = INVALID_SOCKET;
  closesocket(listen_socket);
  WSACleanup();
  AppendLog(L"http worker stopped");
  return 0;
}

DWORD WINAPI ProcessRouterGuardThread(LPVOID) {
  bool disconnect_attempted = false;
  while (WaitForSingleObject(g_stop_event, 500) == WAIT_TIMEOUT) {
    if (!FileExists(kProcessRouterActivePath)) {
      disconnect_attempted = false;
      continue;
    }

    const std::string tunnel_state = QueryServiceState(kTunnelServiceName);
    const std::string router_state = QueryPidFileProcessState(
        kProcessRouterPidPath,
        GetModuleDirectory() +
            L"\\tools\\process-router\\ProxyBridge_CLI.exe");
    if (tunnel_state != "running" || router_state == "running") {
      disconnect_attempted = false;
      continue;
    }
    if (disconnect_attempted) {
      continue;
    }

    disconnect_attempted = true;
    AppendLog(L"process router stopped unexpectedly; disconnecting "
              L"application-only tunnel");
    const int exit_code = RunTaskAction(L"Disconnect", 120000);
    AppendLog(L"process router guard disconnect exit=" +
              std::to_wstring(exit_code));
  }
  AppendLog(L"process router guard stopped");
  return 0;
}

void WINAPI ServiceControlHandler(DWORD control) {
  if (control == SERVICE_CONTROL_STOP) {
    ReportServiceStatus(SERVICE_STOP_PENDING, NO_ERROR, 3000);
    if (g_stop_event != nullptr) {
      SetEvent(g_stop_event);
    }
    if (g_listen_socket != INVALID_SOCKET) {
      closesocket(g_listen_socket);
    }
  }
}

void WINAPI ServiceMain(DWORD, LPWSTR*) {
  g_status_handle = RegisterServiceCtrlHandlerW(kServiceName,
                                                ServiceControlHandler);
  if (g_status_handle == nullptr) {
    return;
  }

  ReportServiceStatus(SERVICE_START_PENDING, NO_ERROR, 3000);
  g_stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (g_stop_event == nullptr) {
    ReportServiceStatus(SERVICE_STOPPED, GetLastError(), 0);
    return;
  }

  g_worker_thread =
      CreateThread(nullptr, 0, HttpWorkerThread, nullptr, 0, nullptr);
  if (g_worker_thread == nullptr) {
    CloseHandle(g_stop_event);
    g_stop_event = nullptr;
    ReportServiceStatus(SERVICE_STOPPED, GetLastError(), 0);
    return;
  }

  g_guard_thread =
      CreateThread(nullptr, 0, ProcessRouterGuardThread, nullptr, 0, nullptr);
  if (g_guard_thread == nullptr) {
    const DWORD guard_error = GetLastError();
    SetEvent(g_stop_event);
    if (g_listen_socket != INVALID_SOCKET) {
      closesocket(g_listen_socket);
    }
    WaitForSingleObject(g_worker_thread, 5000);
    CloseHandle(g_worker_thread);
    CloseHandle(g_stop_event);
    g_worker_thread = nullptr;
    g_stop_event = nullptr;
    ReportServiceStatus(SERVICE_STOPPED, guard_error, 0);
    return;
  }

  ReportServiceStatus(SERVICE_RUNNING, NO_ERROR, 0);
  WaitForSingleObject(g_stop_event, INFINITE);
  ReportServiceStatus(SERVICE_STOP_PENDING, NO_ERROR, 3000);
  if (g_listen_socket != INVALID_SOCKET) {
    closesocket(g_listen_socket);
  }
  WaitForSingleObject(g_worker_thread, 5000);
  WaitForSingleObject(g_guard_thread, 5000);
  CloseHandle(g_worker_thread);
  CloseHandle(g_guard_thread);
  CloseHandle(g_stop_event);
  g_worker_thread = nullptr;
  g_guard_thread = nullptr;
  g_stop_event = nullptr;
  ReportServiceStatus(SERVICE_STOPPED, NO_ERROR, 0);
}

void ParseCommandLine() {
  g_task_script_path = DefaultTaskScriptPath();

  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return;
  }

  for (int i = 1; i < argc; ++i) {
    const std::wstring arg = argv[i];
    if (arg == L"--task-script" && i + 1 < argc) {
      g_task_script_path = argv[++i];
    }
  }

  LocalFree(argv);
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  ParseCommandLine();

  SERVICE_TABLE_ENTRYW service_table[] = {
      {const_cast<LPWSTR>(kServiceName), ServiceMain},
      {nullptr, nullptr},
  };

  if (!StartServiceCtrlDispatcherW(service_table)) {
    AppendLog(L"StartServiceCtrlDispatcher failed err=" +
              std::to_wstring(GetLastError()));
    return 1;
  }

  return 0;
}
