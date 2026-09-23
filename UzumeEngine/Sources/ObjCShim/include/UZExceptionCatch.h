//
//  UZExceptionCatch.h
//  Uzume — BUG-103
//
//  Swift cannot catch an Objective-C NSException. Several AVFoundation calls
//  report failure by raising one — `AVAudioPlayerNode.play()` raises
//  `com.apple.coreaudio.avfaudio` ("player did not see an IO cycle",
//  "required condition is false: _engine != nil"). An NSException unwinding
//  past Swift frames terminates the process, so a shipped call site has no way
//  to report the failure. This is the whole reason the target exists.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Run `body`, converting any raised `NSException` into an `NSError`.
///
/// Returns `YES` when `body` completed without raising. Returns `NO` and
/// populates `error` (domain `UZExceptionCatchErrorDomain`) when it raised;
/// the exception's `name`, `reason` and `callStackSymbols` are carried in
/// `userInfo` so the caller can log what AVFoundation objected to.
///
/// Only `NSException` is caught. C++ exceptions, signals and traps are not,
/// and must not be: they are not failure reports.
BOOL UZRunCatchingNSException(void (NS_NOESCAPE ^body)(void),
                              NSError *_Nullable *_Nullable error);

extern NSErrorDomain const UZExceptionCatchErrorDomain;
extern NSErrorUserInfoKey const UZExceptionNameKey;
extern NSErrorUserInfoKey const UZExceptionCallStackKey;

NS_ASSUME_NONNULL_END
