#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <shellapi.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <string>
#include <vector>

#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "ws2_32.lib")

namespace {

constexpr wchar_t kServiceName[] = L"GreenVPNService";
constexpr wchar_t kTunnelServiceName[] = L"WireGuardTunnel$BlueVPNDev1";
constexpr unsigned short kPort = 48737;

SERVICE_STATUS_HANDLE g_status_handle = nullptr;
SERVICE_STATUS g_status = {};
HANDLE g_stop_event = nullptr;
HANDLE g_worker_thread = nullptr;
SOCKET g_listen_socket = INVALID_SOCKET;
std::wstring g_task_script_path;

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
  CreateDirectoryW(L"C:\\ProgramData\\BlueVPN", nullptr);
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
  HANDLE file = CreateFileW(L"C:\\ProgramData\\BlueVPN\\backend.log",
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

int RunTaskAction(const wchar_t* action, DWORD timeout_ms) {
  if (g_task_script_path.empty() || !FileExists(g_task_script_path)) {
    AppendLog(L"task script missing: " + g_task_script_path);
    return 3;
  }

  const std::wstring powershell = GetPowerShellPath();
  std::wstring command = QuoteArg(powershell) +
                         L" -NoProfile -ExecutionPolicy Bypass -File " +
                         QuoteArg(g_task_script_path) + L" -Action " + action;

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

std::string QueryTunnelStatusJson() {
  std::string state = "missing";
  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (scm != nullptr) {
    SC_HANDLE svc = OpenServiceW(scm, kTunnelServiceName, SERVICE_QUERY_STATUS);
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

  return std::string("{\"ok\":true,\"service\":\"GreenVPNService\",") +
         "\"tunnelService\":\"WireGuardTunnel$BlueVPNDev1\"," +
         "\"tunnelState\":\"" + state + "\"}";
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
  const std::string lower = LowerAscii(first_line);

  if (lower.rfind("get /ping ", 0) == 0 ||
      lower.rfind("get /ping?", 0) == 0) {
    SendHttp(client, 200, "OK",
             "{\"ok\":true,\"service\":\"GreenVPNService\"}");
    return;
  }

  if (lower.rfind("get /status ", 0) == 0 ||
      lower.rfind("get /status?", 0) == 0) {
    SendHttp(client, 200, "OK", QueryTunnelStatusJson());
    return;
  }

  if (lower.rfind("post /connect ", 0) == 0 ||
      lower.rfind("get /connect ", 0) == 0) {
    const int exit_code = RunTaskAction(L"Connect", 120000);
    if (exit_code == 0) {
      SendHttp(client, 200, "OK",
               TaskResultJson(true, exit_code, "connect task accepted"));
    } else if (exit_code == 2) {
      SendHttp(client, 409, "Conflict",
               TaskResultJson(false, exit_code, "another VPN is active"));
    } else {
      SendHttp(client, 500, "Internal Server Error",
               TaskResultJson(false, exit_code, "connect task failed"));
    }
    return;
  }

  if (lower.rfind("post /disconnect ", 0) == 0 ||
      lower.rfind("get /disconnect ", 0) == 0) {
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
    AppendLog(L"bind failed on 127.0.0.1:48737");
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
  AppendLog(L"listening on 127.0.0.1:48737 task=" + g_task_script_path);

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

  ReportServiceStatus(SERVICE_RUNNING, NO_ERROR, 0);
  WaitForSingleObject(g_stop_event, INFINITE);
  ReportServiceStatus(SERVICE_STOP_PENDING, NO_ERROR, 3000);
  if (g_listen_socket != INVALID_SOCKET) {
    closesocket(g_listen_socket);
  }
  WaitForSingleObject(g_worker_thread, 5000);
  CloseHandle(g_worker_thread);
  CloseHandle(g_stop_event);
  g_worker_thread = nullptr;
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
