#include "windows_security_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <userconsentverifierinterop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Security.Credentials.UI.h>
#include <winrt/base.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

namespace {

constexpr char kChannelName[] = "personal_os/internal/windows_vault";
constexpr char kProviderUnavailable[] = "security.provider_unavailable";
constexpr char kUnlockUnavailable[] = "security.unlock_unavailable";
constexpr char kUnlockCancelled[] = "security.unlock_cancelled";
constexpr char kUnlockDenied[] = "security.unlock_denied";
constexpr std::chrono::seconds kTicketLifetime{60};
constexpr size_t kMaximumReasonBytes = 256;

using FlutterResult = flutter::MethodResult<flutter::EncodableValue>;
using FlutterResultPtr = std::unique_ptr<FlutterResult>;
using UserConsentVerifier =
    winrt::Windows::Security::Credentials::UI::UserConsentVerifier;
using UserConsentVerifierAvailability =
    winrt::Windows::Security::Credentials::UI::UserConsentVerifierAvailability;
using UserConsentVerificationResult =
    winrt::Windows::Security::Credentials::UI::UserConsentVerificationResult;

struct ChannelState {
  std::atomic_bool active{true};
};

std::mutex g_state_mutex;
std::unordered_map<flutter::BinaryMessenger*, std::shared_ptr<ChannelState>>
    g_states;

void SendErrorIfActive(const std::shared_ptr<ChannelState>& state,
                       FlutterResult* result, const char* code) {
  if (state->active.load(std::memory_order_acquire)) {
    result->Error(code);
  }
}

void SendSuccessIfActive(const std::shared_ptr<ChannelState>& state,
                         FlutterResult* result,
                         flutter::EncodableMap response) {
  if (state->active.load(std::memory_order_acquire)) {
    result->Success(flutter::EncodableValue(std::move(response)));
  }
}

bool IsAvailable(UserConsentVerifierAvailability availability) {
  return availability == UserConsentVerifierAvailability::Available;
}

flutter::EncodableMap CapabilityResponse(
    UserConsentVerifierAvailability availability) {
  const bool user_authentication_available = IsAvailable(availability);
  flutter::EncodableMap response;
  // UserConsentVerifier proves user presence but does not attest TPM-backed key
  // storage. Hardware protection stays unavailable until a separate key adapter
  // can prove it at runtime.
  response[flutter::EncodableValue("protectionLevel")] =
      flutter::EncodableValue("unavailable");
  response[flutter::EncodableValue("userAuthenticationAvailable")] =
      flutter::EncodableValue(user_authentication_available);
  // The verifier may choose PIN, Windows Hello, or biometrics. We cannot prove
  // that a distinct fallback device credential is configured, so do not claim
  // that narrower capability.
  response[flutter::EncodableValue("deviceCredentialAvailable")] =
      flutter::EncodableValue(false);
  response[flutter::EncodableValue("nonExportableKeys")] =
      flutter::EncodableValue(false);
  response[flutter::EncodableValue("atomicDeviceRevocation")] =
      flutter::EncodableValue(false);
  return response;
}

std::string NewOpaqueTicketId() {
  GUID guid{};
  if (FAILED(::CoCreateGuid(&guid))) {
    return {};
  }
  wchar_t buffer[39]{};
  if (::StringFromGUID2(guid, buffer, 39) <= 0) {
    return {};
  }
  return winrt::to_string(winrt::hstring(buffer));
}

int64_t TicketExpiryMilliseconds() {
  const auto expires_at =
      std::chrono::system_clock::now() + kTicketLifetime;
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             expires_at.time_since_epoch())
      .count();
}

bool ReadAuthenticationArguments(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::string* reason, bool* allow_device_credential) {
  const auto* arguments =
      std::get_if<flutter::EncodableMap>(call.arguments());
  if (arguments == nullptr) {
    return false;
  }

  const auto reason_it =
      arguments->find(flutter::EncodableValue("reason"));
  const auto credential_it =
      arguments->find(flutter::EncodableValue("allowDeviceCredential"));
  if (reason_it == arguments->end() || credential_it == arguments->end()) {
    return false;
  }

  const auto* reason_value = std::get_if<std::string>(&reason_it->second);
  const auto* credential_value = std::get_if<bool>(&credential_it->second);
  if (reason_value == nullptr || credential_value == nullptr ||
      reason_value->empty() || reason_value->size() > kMaximumReasonBytes) {
    return false;
  }

  *reason = *reason_value;
  *allow_device_credential = *credential_value;
  return true;
}

winrt::fire_and_forget InspectCapabilitiesAsync(
    std::shared_ptr<ChannelState> state, FlutterResultPtr result) {
  try {
    const auto availability =
        co_await UserConsentVerifier::CheckAvailabilityAsync();
    SendSuccessIfActive(state, result.get(), CapabilityResponse(availability));
  } catch (...) {
    SendErrorIfActive(state, result.get(), kProviderUnavailable);
  }
}

winrt::fire_and_forget AuthenticateAsync(
    std::shared_ptr<ChannelState> state, HWND owner_window, std::string reason,
    bool allow_device_credential, FlutterResultPtr result) {
  try {
    if (owner_window == nullptr || !allow_device_credential) {
      SendErrorIfActive(state, result.get(), kUnlockUnavailable);
      co_return;
    }

    const auto availability =
        co_await UserConsentVerifier::CheckAvailabilityAsync();
    if (!IsAvailable(availability)) {
      SendErrorIfActive(state, result.get(), kUnlockUnavailable);
      co_return;
    }

    const auto message = winrt::to_hstring(reason);
    const auto interop = winrt::get_activation_factory<
        UserConsentVerifier, ::IUserConsentVerifierInterop>();
    const auto operation = winrt::capture<
        winrt::Windows::Foundation::IAsyncOperation<
            UserConsentVerificationResult>>(
        interop,
        &::IUserConsentVerifierInterop::RequestVerificationForWindowAsync,
        owner_window,
        reinterpret_cast<HSTRING>(winrt::get_abi(message)));
    const auto verification = co_await operation;

    if (!state->active.load(std::memory_order_acquire)) {
      co_return;
    }

    switch (verification) {
      case UserConsentVerificationResult::Verified: {
        const std::string ticket_id = NewOpaqueTicketId();
        if (ticket_id.empty()) {
          result->Error(kProviderUnavailable);
          co_return;
        }
        flutter::EncodableMap response;
        response[flutter::EncodableValue("id")] =
            flutter::EncodableValue(ticket_id);
        response[flutter::EncodableValue("expiresAt")] =
            flutter::EncodableValue(TicketExpiryMilliseconds());
        result->Success(flutter::EncodableValue(std::move(response)));
        co_return;
      }
      case UserConsentVerificationResult::Canceled:
        result->Error(kUnlockCancelled);
        co_return;
      case UserConsentVerificationResult::RetriesExhausted:
        result->Error(kUnlockDenied);
        co_return;
      case UserConsentVerificationResult::DeviceBusy:
      case UserConsentVerificationResult::DeviceNotPresent:
      case UserConsentVerificationResult::DisabledByPolicy:
      case UserConsentVerificationResult::NotConfiguredForUser:
      default:
        result->Error(kUnlockUnavailable);
        co_return;
    }
  } catch (...) {
    SendErrorIfActive(state, result.get(), kProviderUnavailable);
  }
}

void HandleMethodCall(
    const std::shared_ptr<ChannelState>& state, HWND owner_window,
    const flutter::MethodCall<flutter::EncodableValue>& call,
    FlutterResultPtr result) {
  if (!state->active.load(std::memory_order_acquire)) {
    return;
  }

  if (call.method_name() == "inspectCapabilities") {
    InspectCapabilitiesAsync(state, std::move(result));
    return;
  }

  if (call.method_name() == "authenticate") {
    std::string reason;
    bool allow_device_credential = false;
    if (!ReadAuthenticationArguments(
            call, &reason, &allow_device_credential)) {
      result->Error(kProviderUnavailable);
      return;
    }
    AuthenticateAsync(state, owner_window, std::move(reason),
                      allow_device_credential, std::move(result));
    return;
  }

  // The Windows native adapter intentionally does not implement key or Vault
  // operations yet. Returning a stable error is safer than NotImplemented:
  // callers cannot mistake partial platform support for a usable secure Vault.
  result->Error(kProviderUnavailable);
}

}  // namespace

void RegisterWindowsSecurityChannel(flutter::BinaryMessenger* messenger,
                                    HWND owner_window) {
  if (messenger == nullptr || owner_window == nullptr) {
    return;
  }

  UnregisterWindowsSecurityChannel(messenger);

  auto state = std::make_shared<ChannelState>();
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_states[messenger] = state;
  }

  flutter::MethodChannel<flutter::EncodableValue> channel(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler(
      [state, owner_window](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          FlutterResultPtr result) {
        HandleMethodCall(state, owner_window, call, std::move(result));
      });
}

void UnregisterWindowsSecurityChannel(flutter::BinaryMessenger* messenger) {
  if (messenger == nullptr) {
    return;
  }

  std::shared_ptr<ChannelState> state;
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    const auto it = g_states.find(messenger);
    if (it != g_states.end()) {
      state = it->second;
      g_states.erase(it);
    }
  }
  if (state != nullptr) {
    state->active.store(false, std::memory_order_release);
  }

  flutter::MethodChannel<flutter::EncodableValue> channel(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler(nullptr);
}
