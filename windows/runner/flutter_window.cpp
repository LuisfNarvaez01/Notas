#include "flutter_window.h"
#include <optional>
#include <shellapi.h>
#include <flutter/standard_method_codec.h>
#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project) : project_(project) {}
FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) return false;
  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(frame.right-frame.left, frame.bottom-frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) return false;
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  native_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(flutter_controller_->engine()->messenger(), "dev.hilva/native", &flutter::StandardMethodCodec::GetInstance());
  native_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "initialText") { result->Success(); }
    else if (call.method_name() == "setAutoStart") {
      const auto enabled = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
      if (!enabled) { result->Error("ARGUMENT", "Expected boolean"); return; }
      HKEY key;
      auto status = RegCreateKeyEx(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr);
      if (status != ERROR_SUCCESS) { result->Error("REGISTRY", "Cannot access startup settings"); return; }
      if (*enabled) {
        wchar_t exe[MAX_PATH]; GetModuleFileName(nullptr, exe, MAX_PATH);
        const std::wstring command = L"\"" + std::wstring(exe) + L"\"";
        status = RegSetValueEx(key, L"Hilva", 0, REG_SZ, reinterpret_cast<const BYTE*>(command.c_str()), static_cast<DWORD>((command.size()+1)*sizeof(wchar_t)));
      } else {
        status = RegDeleteValue(key, L"Hilva");
        if (status == ERROR_FILE_NOT_FOUND) status = ERROR_SUCCESS;
      }
      RegCloseKey(key);
      if (status == ERROR_SUCCESS) result->Success(); else result->Error("REGISTRY", "Cannot update startup settings");
    } else { result->NotImplemented(); }
  });
  RegisterHotKey(GetHandle(), 1, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, 'H');
  tray_.cbSize = sizeof(tray_); tray_.hWnd = GetHandle(); tray_.uID = 1;
  tray_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP; tray_.uCallbackMessage = WM_APP + 1;
  tray_.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_.szTip, L"Hilva · Ctrl+Shift+H");
  Shell_NotifyIcon(NIM_ADD, &tray_);
  flutter_controller_->engine()->SetNextFrameCallback([&]() { Show(); });
  flutter_controller_->ForceRedraw();
  return true;
}
void FlutterWindow::OnDestroy() {
  UnregisterHotKey(GetHandle(), 1);
  Shell_NotifyIcon(NIM_DELETE, &tray_);
  native_channel_.reset();
  flutter_controller_.reset();
  Win32Window::OnDestroy();
}
LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) noexcept {
  if (flutter_controller_) {
    auto result = flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) return *result;
  }
  if (message == WM_HOTKEY && wparam == 1) {
    ShowWindow(hwnd, SW_RESTORE); SetForegroundWindow(hwnd);
    native_channel_->InvokeMethod("capture", std::make_unique<flutter::EncodableValue>(""));
    return 0;
  }
  if (message == WM_APP + 1) {
    if (lparam == WM_LBUTTONUP) { ShowWindow(hwnd, SW_RESTORE); SetForegroundWindow(hwnd); }
    if (lparam == WM_RBUTTONUP) {
      HMENU menu = CreatePopupMenu();
      AppendMenu(menu, MF_STRING, 1, L"Abrir Hilva");
      AppendMenu(menu, MF_STRING, 2, L"Nueva captura");
      AppendMenu(menu, MF_STRING, 3, L"Salir");
      POINT point; GetCursorPos(&point); SetForegroundWindow(hwnd);
      const int selected = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, point.x, point.y, 0, hwnd, nullptr);
      DestroyMenu(menu);
      if (selected == 3) { DestroyWindow(hwnd); }
      else if (selected != 0) { ShowWindow(hwnd, SW_RESTORE); SetForegroundWindow(hwnd);
        if (selected == 2) native_channel_->InvokeMethod("capture", std::make_unique<flutter::EncodableValue>("")); }
    }
    return 0;
  }
  if (message == WM_SYSCOMMAND && (wparam & 0xfff0) == SC_MINIMIZE) { ShowWindow(hwnd, SW_HIDE); return 0; }
  if (message == WM_FONTCHANGE && flutter_controller_) flutter_controller_->engine()->ReloadSystemFonts();
  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
