#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "green_vpn_runtime_config.h"
#include "utils.h"

namespace {

constexpr const wchar_t kSingleInstanceMutexName[] =
    L"Local\\" GREENVPN_RUNTIME_INSTANCE_ID_W L".SingleInstance";
constexpr const wchar_t kRunnerWindowClassName[] =
    L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr const wchar_t kAppWindowTitle[] = GREENVPN_RUNTIME_PRODUCT_NAME_W;

bool IsBackgroundLaunch(const std::wstring& raw_command_line,
                        int show_command) {
  return raw_command_line.find(L"--background") != std::wstring::npos ||
         raw_command_line.find(L"--tray") != std::wstring::npos ||
         show_command == SW_HIDE;
}

bool IsShutdownRequest(const std::wstring& raw_command_line) {
  return raw_command_line.find(L"--shutdown-existing") != std::wstring::npos;
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

bool ShutdownExistingGreenVpnWindow() {
  for (int attempt = 0; attempt < 40; ++attempt) {
    HWND existing_window = FindExistingGreenVpnWindow();
    if (existing_window) {
      DWORD process_id = 0;
      GetWindowThreadProcessId(existing_window, &process_id);
      DWORD_PTR ignored = 0;
      if (!SendMessageTimeoutW(existing_window, kGreenVpnShutdownMessage, 0, 0,
                               SMTO_ABORTIFHUNG, 5000, &ignored)) {
        return false;
      }
      if (process_id != 0) {
        HANDLE process =
            OpenProcess(SYNCHRONIZE, FALSE, process_id);
        if (process) {
          const DWORD wait_result = WaitForSingleObject(process, 10000);
          CloseHandle(process);
          return wait_result == WAIT_OBJECT_0;
        }
      }
      return true;
    }
    Sleep(50);
  }
  return true;
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
  const bool shutdown_requested = IsShutdownRequest(raw_command_line);

  HANDLE single_instance_mutex =
      CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  if (!single_instance_mutex) {
    return EXIT_FAILURE;
  }
  const DWORD mutex_wait_result =
      WaitForSingleObject(single_instance_mutex, 0);
  const bool owns_single_instance_mutex =
      mutex_wait_result == WAIT_OBJECT_0 || mutex_wait_result == WAIT_ABANDONED;
  if (mutex_wait_result == WAIT_FAILED) {
    CloseHandle(single_instance_mutex);
    return EXIT_FAILURE;
  }
  if (!owns_single_instance_mutex) {
    if (shutdown_requested) {
      const bool stopped = ShutdownExistingGreenVpnWindow();
      CloseHandle(single_instance_mutex);
      return stopped ? EXIT_SUCCESS : EXIT_FAILURE;
    }
    if (!start_hidden) {
      RestoreExistingGreenVpnWindow();
    }
    CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }
  if (shutdown_requested) {
    ReleaseMutex(single_instance_mutex);
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
  const HRESULT com_result =
      ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, start_hidden);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(980, 720);

  if (!window.Create(kAppWindowTitle, origin, size)) {
    if (SUCCEEDED(com_result)) {
      ::CoUninitialize();
    }
    ReleaseMutex(single_instance_mutex);
    CloseHandle(single_instance_mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (SUCCEEDED(com_result)) {
    ::CoUninitialize();
  }
  ReleaseMutex(single_instance_mutex);
  CloseHandle(single_instance_mutex);
  return EXIT_SUCCESS;
}
