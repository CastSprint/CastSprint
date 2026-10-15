// csp_objc_guard.m — Objective-C Exception Safety Wrapper for CoreAudio / AVFoundation
#import <Foundation/Foundation.h>
#import "CCastSprintProtocol.h"

#if defined(__APPLE__)
bool csp_safe_audio_schedule(void (^block)(void), char* err_buf, size_t err_len) {
    if (!block) return false;
    @try {
        block();
        return true;
    } @catch (NSException *exception) {
        if (err_buf && err_len > 0) {
            snprintf(err_buf, err_len, "%s: %s",
                     [[exception name] UTF8String] ?: "Unknown",
                     [[exception reason] UTF8String] ?: "Unknown reason");
        }
        return false;
    }
}
#endif
