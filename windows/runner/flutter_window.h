#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that hosts a Flutter view and a system tray (notification area) icon.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // --- System tray (channel "mflab/tray") ---
  void HandleTrayCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  bool AddTrayIcon();
  void RemoveTrayIcon();
  void SetTrayTooltip(const std::wstring& text);
  void ShowBalloon(const std::wstring& title, const std::wstring& text);
  void ShowMainWindow();
  void ShowTrayMenu();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> tray_channel_;
  flutter::EncodableList tray_menu_;
  std::wstring tray_tooltip_ = L"MF Lab";
  bool tray_added_ = false;
  bool close_to_tray_ = false;
  bool quitting_ = false;
  bool balloon_shown_ = false;
  UINT taskbar_created_msg_ = 0;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
