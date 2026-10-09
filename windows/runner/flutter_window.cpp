#include "flutter_window.h"

#include <shellapi.h>

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayIconId = 1;

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return L"";
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                              nullptr, 0);
  std::wstring w(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), &w[0],
                      n);
  return w;
}

int AsInt(const flutter::EncodableValue* v, int fallback = 0) {
  if (!v) return fallback;
  if (const auto* i = std::get_if<int32_t>(v)) return *i;
  if (const auto* l = std::get_if<int64_t>(v)) return static_cast<int>(*l);
  return fallback;
}

const flutter::EncodableValue* Find(const flutter::EncodableMap& m,
                                    const char* key) {
  auto it = m.find(flutter::EncodableValue(std::string(key)));
  return it == m.end() ? nullptr : &it->second;
}

std::string AsString(const flutter::EncodableValue* v) {
  if (!v) return "";
  if (const auto* s = std::get_if<std::string>(v)) return *s;
  return "";
}

bool AsBool(const flutter::EncodableValue* v, bool fallback) {
  if (!v) return fallback;
  if (const auto* b = std::get_if<bool>(v)) return *b;
  return fallback;
}

// Builds a native popup menu from the list sent by Dart.
void BuildMenu(const flutter::EncodableList& items, HMENU menu) {
  for (const auto& entry : items) {
    const auto* m = std::get_if<flutter::EncodableMap>(&entry);
    if (!m) continue;
    std::string type = AsString(Find(*m, "type"));
    if (type == "sep") {
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      continue;
    }
    std::wstring label = Utf8ToWide(AsString(Find(*m, "label")));
    UINT flags = MF_STRING;
    if (!AsBool(Find(*m, "enabled"), true)) flags |= MF_GRAYED;
    if (type == "submenu") {
      HMENU sub = CreatePopupMenu();
      if (const auto* ch = Find(*m, "children")) {
        if (const auto* list = std::get_if<flutter::EncodableList>(ch)) {
          BuildMenu(*list, sub);
        }
      }
      AppendMenuW(menu, flags | MF_POPUP, reinterpret_cast<UINT_PTR>(sub),
                  label.c_str());
    } else {
      AppendMenuW(menu, flags, static_cast<UINT_PTR>(AsInt(Find(*m, "id"))),
                  label.c_str());
    }
  }
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

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

  taskbar_created_msg_ = RegisterWindowMessageW(L"TaskbarCreated");
  tray_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "mflab/tray",
          &flutter::StandardMethodCodec::GetInstance());
  tray_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleTrayCall(call, std::move(result)); });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  tray_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

// ------------------------------------------------------------------ tray

bool FlutterWindow::AddTrayIcon() {
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = GetHandle();
  nid.uID = kTrayIconId;
  nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid.uCallbackMessage = kTrayMessage;
  nid.hIcon = LoadIconW(GetModuleHandleW(nullptr),
                        MAKEINTRESOURCEW(IDI_APP_ICON));
  wcsncpy_s(nid.szTip, tray_tooltip_.c_str(), _TRUNCATE);
  tray_added_ = Shell_NotifyIconW(NIM_ADD, &nid) == TRUE;
  return tray_added_;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_added_) return;
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = GetHandle();
  nid.uID = kTrayIconId;
  Shell_NotifyIconW(NIM_DELETE, &nid);
  tray_added_ = false;
}

void FlutterWindow::SetTrayTooltip(const std::wstring& text) {
  tray_tooltip_ = text;
  if (!tray_added_) return;
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = GetHandle();
  nid.uID = kTrayIconId;
  nid.uFlags = NIF_TIP;
  wcsncpy_s(nid.szTip, tray_tooltip_.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &nid);
}

void FlutterWindow::ShowBalloon(const std::wstring& title,
                                const std::wstring& text) {
  if (!tray_added_) return;
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = GetHandle();
  nid.uID = kTrayIconId;
  nid.uFlags = NIF_INFO;
  nid.dwInfoFlags = NIIF_INFO;
  wcsncpy_s(nid.szInfoTitle, title.c_str(), _TRUNCATE);
  wcsncpy_s(nid.szInfo, text.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &nid);
}

void FlutterWindow::ShowMainWindow() {
  HWND hwnd = GetHandle();
  ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(hwnd);
}

void FlutterWindow::ShowTrayMenu() {
  // Let Dart refresh the service list for the next time the menu opens.
  if (tray_channel_) {
    tray_channel_->InvokeMethod("beforeMenu", nullptr);
  }
  HWND hwnd = GetHandle();
  HMENU menu = CreatePopupMenu();
  BuildMenu(tray_menu_, menu);
  POINT pt;
  GetCursorPos(&pt);
  // Required so the menu closes when the user clicks elsewhere.
  SetForegroundWindow(hwnd);
  UINT cmd = static_cast<UINT>(
      TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN,
                     pt.x, pt.y, 0, hwnd, nullptr));
  PostMessageW(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);
  if (cmd > 0 && tray_channel_) {
    tray_channel_->InvokeMethod(
        "menuClick", std::make_unique<flutter::EncodableValue>(
                         static_cast<int32_t>(cmd)));
  }
}

void FlutterWindow::HandleTrayCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& name = call.method_name();
  const auto* args = call.arguments();
  const flutter::EncodableMap* map =
      args ? std::get_if<flutter::EncodableMap>(args) : nullptr;

  if (name == "init") {
    if (map) {
      std::string tip = AsString(Find(*map, "tooltip"));
      if (!tip.empty()) tray_tooltip_ = Utf8ToWide(tip);
    }
    if (!tray_added_) AddTrayIcon();
    result->Success(flutter::EncodableValue(tray_added_));
  } else if (name == "setMenu") {
    if (args) {
      if (const auto* list = std::get_if<flutter::EncodableList>(args)) {
        tray_menu_ = *list;
      }
    }
    result->Success();
  } else if (name == "setTooltip") {
    if (map) SetTrayTooltip(Utf8ToWide(AsString(Find(*map, "text"))));
    result->Success();
  } else if (name == "setCloseToTray") {
    if (map) close_to_tray_ = AsBool(Find(*map, "value"), false);
    result->Success();
  } else if (name == "show") {
    ShowMainWindow();
    result->Success();
  } else if (name == "quit") {
    quitting_ = true;
    DestroyWindow(GetHandle());
    result->Success();
  } else {
    result->NotImplemented();
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Closing the window while services run only hides it; the tray icon stays.
  if (message == WM_CLOSE && close_to_tray_ && !quitting_ && tray_added_) {
    ShowWindow(hwnd, SW_HIDE);
    if (!balloon_shown_) {
      balloon_shown_ = true;
      ShowBalloon(L"MF Lab arka planda çalışıyor",
                  L"Servisler çalışmaya devam ediyor. Menü için saatin "
                  L"yanındaki MF Lab simgesine sağ tıkla.");
    }
    return 0;
  }

  if (message == kTrayMessage) {
    switch (LOWORD(lparam)) {
      case WM_LBUTTONUP:
      case WM_LBUTTONDBLCLK:
        ShowMainWindow();
        break;
      case WM_RBUTTONUP:
      case WM_CONTEXTMENU:
        ShowTrayMenu();
        break;
    }
    return 0;
  }

  // Explorer restarted: the tray icon must be added again.
  if (taskbar_created_msg_ != 0 && message == taskbar_created_msg_) {
    tray_added_ = false;
    AddTrayIcon();
    return 0;
  }

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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
