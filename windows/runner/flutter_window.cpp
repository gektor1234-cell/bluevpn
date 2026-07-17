#include "flutter_window.h"

#include "green_vpn_runtime_config.h"

#include <fstream>
#include <iterator>
#include <optional>
#include <string>
#include <thread>
#include <windows.h>
#include <winhttp.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayCallbackMessage = WM_APP + 42;
constexpr UINT_PTR kTrayIconId = 1;
constexpr UINT kTrayMenuOpen = 1001;
constexpr UINT kTrayMenuConnect = 1002;
constexpr UINT kTrayMenuDisconnect = 1003;
constexpr UINT kTrayMenuExit = 1004;
constexpr UINT kTrayTaskResultMessage = WM_APP + 43;

std::string ReadLocalServiceToken() {
  std::ifstream file(GREENVPN_RUNTIME_PROGRAM_DATA_ROOT_A "\\service_token",
                     std::ios::binary);
  if (!file) {
    return "";
  }

  std::string token((std::istreambuf_iterator<char>(file)),
                    std::istreambuf_iterator<char>());
  const auto first = token.find_first_not_of(" \t\r\n");
  if (first == std::string::npos) {
    return "";
  }
  const auto last = token.find_last_not_of(" \t\r\n");
  token = token.substr(first, last - first + 1);
  return token.size() >= 24 ? token : "";
}

bool RunLocalVpnTask(const std::wstring& path) {
  HINTERNET session = WinHttpOpen(GREENVPN_RUNTIME_PRODUCT_NAME_W L" tray/1.0",
                                  WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                                  WINHTTP_NO_PROXY_NAME,
                                  WINHTTP_NO_PROXY_BYPASS, 0);
  if (!session) {
    return false;
  }
  WinHttpSetTimeouts(session, 2000, 2000, 2000, 125000);

  HINTERNET connect = WinHttpConnect(
      session, L"127.0.0.1", GREENVPN_RUNTIME_LOCAL_SERVICE_PORT, 0);
  if (!connect) {
    WinHttpCloseHandle(session);
    return false;
  }

  HINTERNET request = WinHttpOpenRequest(
      connect, L"POST", path.c_str(), nullptr, WINHTTP_NO_REFERER,
      WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
  if (!request) {
    WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    return false;
  }

  const std::string token = ReadLocalServiceToken();
  if (token.empty()) {
    WinHttpCloseHandle(request);
    WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    return false;
  }

  std::wstring headers = L"Content-Type: application/json\r\n";
  headers += L"X-GreenVPN-Local-Token: ";
  headers.append(token.begin(), token.end());
  headers += L"\r\n";
  const char body[] = "{}";
  bool success = false;
  if (WinHttpSendRequest(request, headers.c_str(), static_cast<DWORD>(-1),
                         const_cast<char*>(body),
                         static_cast<DWORD>(sizeof(body) - 1),
                         static_cast<DWORD>(sizeof(body) - 1), 0) &&
      WinHttpReceiveResponse(request, nullptr)) {
    DWORD status_code = 0;
    DWORD status_size = sizeof(status_code);
    success = WinHttpQueryHeaders(
                  request,
                  WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                  WINHTTP_HEADER_NAME_BY_INDEX, &status_code, &status_size,
                  WINHTTP_NO_HEADER_INDEX) &&
              status_code >= 200 && status_code < 300;
  }

  WinHttpCloseHandle(request);
  WinHttpCloseHandle(connect);
  WinHttpCloseHandle(session);
  return success;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool start_hidden)
    : project_(project), start_hidden_(start_hidden) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  AddTrayIcon(GetHandle());

  if (!start_hidden_) {
    flutter_controller_->engine()->SetNextFrameCallback([&]() {
      this->Show();
    });
  }

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE:
      if (!exit_requested_) {
        ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      break;

    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case kTrayMenuOpen:
          RestoreFromTray();
          return 0;
        case kTrayMenuConnect:
          RunVpnTask(L"GreenVPNConnect");
          return 0;
        case kTrayMenuDisconnect:
          RunVpnTask(L"GreenVPNDisconnect");
          return 0;
        case kTrayMenuExit:
          exit_requested_ = true;
          Destroy();
          return 0;
      }
      break;

    case kTrayCallbackMessage:
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          RestoreFromTray();
          return 0;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
          ShowTrayMenu(hwnd);
          return 0;
      }
      break;

    case kTrayTaskResultMessage:
      tray_task_running_ = false;
      ShowTrayTaskResult(wparam == TRUE, lparam == TRUE);
      return 0;

    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::AddTrayIcon(HWND window) {
  if (!window || tray_icon_added_) {
    return;
  }

  ZeroMemory(&tray_icon_data_, sizeof(tray_icon_data_));
  tray_icon_data_.cbSize = sizeof(tray_icon_data_);
  tray_icon_data_.hWnd = window;
  tray_icon_data_.uID = kTrayIconId;
  tray_icon_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_data_.uCallbackMessage = kTrayCallbackMessage;
  tray_icon_data_.hIcon =
      LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_icon_data_.szTip, GREENVPN_RUNTIME_PRODUCT_NAME_W);

  tray_icon_added_ = Shell_NotifyIconW(NIM_ADD, &tray_icon_data_) == TRUE;
  if (tray_icon_added_) {
    tray_icon_data_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &tray_icon_data_);
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_added_) {
    return;
  }

  Shell_NotifyIconW(NIM_DELETE, &tray_icon_data_);
  tray_icon_added_ = false;
}

void FlutterWindow::ShowTrayMenu(HWND window) {
  if (!window) {
    return;
  }

  HMENU menu = CreatePopupMenu();
  if (!menu) {
    return;
  }

  AppendMenuW(menu, MF_STRING, kTrayMenuOpen,
              L"\u041e\u0442\u043a\u0440\u044b\u0442\u044c " GREENVPN_RUNTIME_PRODUCT_NAME_W);
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  const UINT task_flags = MF_STRING | (tray_task_running_ ? MF_GRAYED : 0);
  AppendMenuW(menu, task_flags, kTrayMenuConnect,
               L"\u041f\u043e\u0434\u043a\u043b\u044e\u0447\u0438\u0442\u044c VPN");
  AppendMenuW(menu, task_flags, kTrayMenuDisconnect,
               L"\u041e\u0442\u043a\u043b\u044e\u0447\u0438\u0442\u044c VPN");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayMenuExit,
              L"\u0412\u044b\u0445\u043e\u0434");

  POINT cursor{};
  GetCursorPos(&cursor);
  SetForegroundWindow(window);
  TrackPopupMenu(menu, TPM_LEFTALIGN | TPM_BOTTOMALIGN | TPM_RIGHTBUTTON,
                 cursor.x, cursor.y, 0, window, nullptr);
  DestroyMenu(menu);

  // Required by Shell_NotifyIcon context menus so the menu reliably closes.
  PostMessage(window, WM_NULL, 0, 0);
}

void FlutterWindow::RestoreFromTray() {
  HWND window = GetHandle();
  if (!window) {
    return;
  }

  ShowWindow(window, SW_SHOW);
  ShowWindow(window, SW_RESTORE);
  SetForegroundWindow(window);
}

void FlutterWindow::RunVpnTask(const wchar_t* task_name) {
  if (!task_name || !*task_name || tray_task_running_) {
    return;
  }

  std::wstring path;
  bool connecting = false;
  if (wcscmp(task_name, L"GreenVPNConnect") == 0) {
    path = L"/connect";
    connecting = true;
  } else if (wcscmp(task_name, L"GreenVPNDisconnect") == 0) {
    path = L"/disconnect";
  } else {
    return;
  }

  tray_task_running_ = true;
  const HWND window = GetHandle();
  std::thread([window, path, connecting]() {
    const bool success = RunLocalVpnTask(path);
    if (IsWindow(window)) {
      PostMessage(window, kTrayTaskResultMessage, success ? TRUE : FALSE,
                  connecting ? TRUE : FALSE);
    }
  }).detach();
}

void FlutterWindow::ShowTrayTaskResult(bool success, bool connecting) {
  if (!tray_icon_added_) {
    return;
  }

  NOTIFYICONDATAW notification = tray_icon_data_;
  notification.uFlags = NIF_INFO;
  notification.dwInfoFlags = success ? NIIF_INFO : NIIF_ERROR;
  wcscpy_s(notification.szInfoTitle, GREENVPN_RUNTIME_PRODUCT_NAME_W);
  const wchar_t* message = nullptr;
  if (success) {
    message = connecting
                  ? L"VPN \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0451\u043d."
                  : L"VPN \u043e\u0442\u043a\u043b\u044e\u0447\u0451\u043d.";
  } else {
    message = connecting
                  ? L"\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0438\u0442\u044c VPN. \u041e\u0442\u043a\u0440\u043e\u0439\u0442\u0435 \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u0435."
                  : L"\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043e\u0442\u043a\u043b\u044e\u0447\u0438\u0442\u044c VPN. \u041e\u0442\u043a\u0440\u043e\u0439\u0442\u0435 \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u0435.";
  }
  wcscpy_s(notification.szInfo, message);
  Shell_NotifyIconW(NIM_MODIFY, &notification);
}
