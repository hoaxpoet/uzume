#import "UZExceptionCatch.h"

NSErrorDomain const UZExceptionCatchErrorDomain = @"io.uzume.exception-catch";
NSErrorUserInfoKey const UZExceptionNameKey = @"UZExceptionName";
NSErrorUserInfoKey const UZExceptionCallStackKey = @"UZExceptionCallStack";

BOOL UZRunCatchingNSException(void (NS_NOESCAPE ^body)(void),
                              NSError *_Nullable *_Nullable error) {
    @try {
        body();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[NSLocalizedDescriptionKey] =
                exception.reason ?: @"Objective-C exception with no reason";
            info[UZExceptionNameKey] = exception.name ?: @"(unnamed)";
            if (exception.callStackSymbols) {
                info[UZExceptionCallStackKey] = exception.callStackSymbols;
            }
            *error = [NSError errorWithDomain:UZExceptionCatchErrorDomain
                                         code:1
                                     userInfo:info];
        }
        return NO;
    }
}
