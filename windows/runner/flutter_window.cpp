#include "flutter_window.h"

#include <optional>
#include <string>
#include <windows.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayCallbackMessage = WM_APP + 42;
constexpr UINT_PTR kTrayIconId = 1;
constexpr UINT kTrayMenuOpen = 1001;
constexpr UINT kTrayMenuConnect = 1002;
constexpr UINT kTrayMenuDisconnect = 1003;
constexpr UINT kTrayMenuExit = 1004;

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
  wcscpy_s(tray_icon_data_.szTip, L"Green VPN");

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

  AppendMenuW(menu, MF_STRING, kTrayMenuOpen, L"Open Green VPN");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayMenuConnect, L"Connect VPN");
  AppendMenuW(menu, MF_STRING, kTrayMenuDisconnect, L"Disconnect VPN");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayMenuExit, L"Exit");

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
  if (!task_name || !*task_name) {
    return;
  }

  std::wstring params = L"/Run /TN ";
  params += task_name;

  SHELLEXECUTEINFOW exec_info{};
  exec_info.cbSize = sizeof(exec_info);
  exec_info.fMask = SEE_MASK_NOCLOSEPROCESS;
  exec_info.lpVerb = L"open";
  exec_info.lpFile = L"schtasks.exe";
  exec_info.lpParameters = params.c_str();
  exec_info.nShow = SW_HIDE;

  if (ShellExecuteExW(&exec_info) && exec_info.hProcess) {
    CloseHandle(exec_info.hProcess);
  }
}
