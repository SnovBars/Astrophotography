import Foundation

class CrashLogger {
    static let shared = CrashLogger()
    
    func setup() {
        // Вызываем Objective-C метод для перехвата NSException и сигналов
        ObjCCrashLogger.setup()
    }
    
    func writeToFile(message: String) {
        // Перенаправляем вызов в Objective-C
        ObjCCrashLogger.logMessage(message)
    }
}