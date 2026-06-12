#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr const wchar_t kSingleInstanceMutexName[] =
    L"Local\\GreenVPN.SingleInstance";
constexpr const wchar_t kRunnerWindowClassName[] =
    L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr const wchar_t kAppWindowTitle[] = L"Green VPN";

bool IsBackgroundLaunch(const std::wstring& raw_command_line,
                        int show_command) {
  return raw_command_line.find(L"--background") != std::wstring::npos ||
         raw_command_line.find(L"--tray") != std::wstring::npos ||
         show_command == SW_HIDE;
}

BOOL CALLBACK FindExistingGreenVpnWindow(HWND window, LPARAM lparam) {
  if (!IsWindow(window)) {
    return TRUE;
  }

  wchar_t class_name[128] = {};
  wchar_t title[128] = {};
  GetClassNameW(window, class_name, static_cast<int>(std::size(class_name)));
  GetWindowTextW(window, title, static_cast<int>(std::size(title)));

  if (wcscmp(class_name, kRunnerWindowClassName) == 0 &&
      wcscmp(title, kAppWindowTitle) == 0) {
    *reinterpret_cast<HWND*>(lparam) = window;
    return FALSE;
  }
  return TRUE;
}

HWND FindExistingGreenVpnWindow() {
  HWND existing_window = nullptr;
  EnumWindows(FindExistingGreenVpnWindow,
              reinterpret_cast<LPARAM>(&existing_window));
  return existing_window;
}

void RestoreExistingGreenVpnWindow() {
  // The first process may still be creating its Flutter window, so give it a
  // short moment before falling back to a quiet exit.
  for (int attempt = 0; attempt < 20; ++attempt) {
    HWND existing_window = FindExistingGreenVpnWindow();
    if (existing_window) {
      ShowWindow(existing_window, SW_SHOW);
      ShowWindow(existing_window, SW_RESTORE);
      SetForegroundWindow(existing_window);
      return;
    }
    Sleep(50);
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  const std::wstring raw_command_line = command_line ? command_line : L"";
  const bool start_hidden = IsBackgroundLaunch(raw_command_line, show_command);

  HANDLE single_instance_mutex =
      CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (!single_instance_mutex) {
    return EXIT_FAILURE;
  }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    if (!start_hidden) {
      RestoreExistingGreenVpnWindow();
    }
    CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }
  if (FindExistingGreenVpnWindow()) {
    if (!start_hidden) {
      RestoreExistingGreenVpnWindow();
    }
    ReleaseMutex(single_instance_mutex);
    CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, start_hidden);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(980, 720);

  if (!window.Create(L"Green VPN", origin, size)) {

    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ReleaseMutex(single_instance_mutex);
  CloseHandle(single_instance_mutex);
  return EXIT_SUCCESS;
}
