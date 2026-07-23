#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^STNodeLogHandler)(NSString *line);
typedef void (^STNodeCompletionHandler)(int exitCode, NSString * _Nullable error);

@interface STNodeRuntimeBridge : NSObject

@property (atomic, readonly, getter=isStarted) BOOL started;

- (void)startScriptAtPath:(NSString *)scriptPath
                arguments:(NSArray<NSString *> *)arguments
               logHandler:(STNodeLogHandler)logHandler
               completion:(STNodeCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END
