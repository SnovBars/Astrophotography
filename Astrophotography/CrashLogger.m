#import "CrashLogger.h"

// Обработчик системных сигналов (например, когда приложение убивает система)
static void SignalHandler(int signum) {
    NSString *errorMessage = [NSString stringWithFormat:@"🚨 CRASH DETECTED (Signal %d)\nDate: %@\n", signum, [NSDate date]];
    [ObjCCrashLogger logMessage:errorMessage];
    
    // Сбрасываем обработчик и передаем сигнал дальше, чтобы приложение упало как обычно
    signal(signum, SIG_DFL);
    raise(signum);
}

// Обработчик исключений Objective-C (NSException)
static void UncaughtExceptionHandler(NSException *exception) {
    NSString *crashLog = [NSString stringWithFormat:
                          @"🚨 CRASH DETECTED (NSException)\n"
                          @"Date: %@\n"
                          @"Name: %@\n"
                          @"Reason: %@\n"
                          @"Stack Trace:\n%@\n",
                          [NSDate date],
                          exception.name,
                          exception.reason,
                          [exception.callStackSymbols componentsJoinedByString:@"\n"]];
    
    [ObjCCrashLogger logMessage:crashLog];
}

@implementation ObjCCrashLogger

+ (void)setup {
    // Перехват Objective-C исключений
    NSSetUncaughtExceptionHandler(&UncaughtExceptionHandler);
    
    // Перехват фатальных сигналов
    signal(SIGABRT, SignalHandler);
    signal(SIGILL, SignalHandler);
    signal(SIGSEGV, SignalHandler);
    signal(SIGFPE, SignalHandler);
    signal(SIGBUS, SignalHandler);
    signal(SIGPIPE, SignalHandler);
}

+ (void)logMessage:(NSString *)message {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    NSString *logFilePath = [documentsDirectory stringByAppendingPathComponent:@"crash-log.txt"];
    
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], message];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:logFilePath]) {
        [logEntry writeToFile:logFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logFilePath];
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[logEntry dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    }
}

@end