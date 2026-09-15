#ifndef PERSONAL_OS_WINDOWS_SECURITY_CHANNEL_H_
#define PERSONAL_OS_WINDOWS_SECURITY_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

// Registers the private Windows security channel against the current Flutter
// engine. The implementation is deliberately limited to capability inspection
// and user-presence verification; Vault/key operations remain fail-closed.
void RegisterWindowsSecurityChannel(flutter::BinaryMessenger* messenger,
                                    HWND owner_window);

#endif  // PERSONAL_OS_WINDOWS_SECURITY_CHANNEL_H_
