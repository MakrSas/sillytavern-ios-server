#import "NodeRuntimeBridge.h"
#import <NodeMobile/NodeMobile.h>
#import <unistd.h>

@interface STNodeRuntimeBridge ()
@property (atomic, readwrite, getter=isStarted) BOOL started;
@property (nonatomic, strong) NSFileHandle *readHandle;
@property (nonatomic, copy) STNodeLogHandler logHandler;
@end

@implementation STNodeRuntimeBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        _started = NO;
    }
    return self;
}

- (void)startScriptAtPath:(NSString *)scriptPath
                arguments:(NSArray<NSString *> *)arguments
               logHandler:(STNodeLogHandler)logHandler
               completion:(STNodeCompletionHandler)completion {
    @synchronized (self) {
        if (self.started) {
            completion(-1, @"Node runtime можно запускать только один раз за жизненный цикл приложения.");
            return;
        }
        self.started = YES;
    }

    self.logHandler = logHandler;
    [self installOutputCapture];

    dispatch_queue_t queue = dispatch_queue_create("app.sillytavern.node-runtime", DISPATCH_QUEUE_SERIAL);
    dispatch_async(queue, ^{
        NSMutableArray<NSString *> *allArguments = [NSMutableArray arrayWithObjects:@"node", scriptPath, nil];
        [allArguments addObjectsFromArray:arguments];

        int argc = (int)allArguments.count;
        char **argv = (char **)calloc((size_t)argc + 1, sizeof(char *));
        for (int index = 0; index < argc; index++) {
            argv[index] = strdup(allArguments[index].UTF8String);
        }

        int exitCode = node_start(argc, argv);

        for (int index = 0; index < argc; index++) {
            free(argv[index]);
        }
        free(argv);

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(exitCode, nil);
        });
    });
}

- (void)installOutputCapture {
    int descriptors[2];
    if (pipe(descriptors) != 0) {
        return;
    }

    dup2(descriptors[1], STDOUT_FILENO);
    dup2(descriptors[1], STDERR_FILENO);
    close(descriptors[1]);
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    self.readHandle = [[NSFileHandle alloc] initWithFileDescriptor:descriptors[0] closeOnDealloc:YES];
    __weak typeof(self) weakSelf = self;
    self.readHandle.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        if (data.length == 0) {
            return;
        }
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (text.length == 0) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.logHandler) {
                weakSelf.logHandler(text);
            }
        });
    };
}

@end
