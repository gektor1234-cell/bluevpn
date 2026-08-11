#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <shellapi.h>

#include <memory>

#include "win32_window.h"

constexpr UINT kGreenVpnShutdownMessage = WM_APP + 44;

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project,
                         bool start_hidden = false);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;
  bool start_hidden_ = false;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  void AddTrayIcon(HWND window);
  void RemoveTrayIcon();
  void ScheduleTrayIconRetry(HWND window);
  void ShowTrayMenu(HWND window);
  void RestoreFromTray();
  void RunVpnTask(const wchar_t* task_name);
  void RequestDisconnectAndExit();
  void ShowTrayTaskResult(bool success, bool connecting);
  void ExitApplication();

  bool tray_icon_added_ = false;
  bool tray_stale_cleanup_done_ = false;
  int tray_icon_add_attempts_ = 0;
  bool tray_task_running_ = false;
  bool exit_after_tray_task_ = false;
  bool exit_requested_ = false;
  enum class CloseBehavior {
    kMinimizeToTray,
    kAsk,
    kDisconnectAndExit,
  };
  CloseBehavior close_behavior_ = CloseBehavior::kMinimizeToTray;
  NOTIFYICONDATAW tray_icon_data_{};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
