//
//  MetricsCollector.m
//  Monal
//
//  isaCloud: coleta de métricas por build para avaliar consumo de recursos
//  (memória, CPU, bateria/térmica, banco) e recebe as métricas oficiais do
//  sistema pelo MetricKit. Os dados ficam em JSON no container do App Group
//  (<grupo>/metrics/) e são exportados pelo Depuração, de onde seguem para o
//  harness em tools/metrics-harness (InfluxDB + Grafana).
//
//  Decisões:
//  - amostra por evento (app ativo/para segundo plano) e a cada 5 minutos com o
//    app ativo: dá série temporal curta sem acordar o app para isso;
//  - CPU é delta entre amostras (task_basic_info), que é o que interessa;
//  - energia/bateria "oficiais" vêm do MetricKit: as APIs públicas por processo
//    não expõem energia de forma estável em todas as versões;
//  - cada amostra leva o CFBundleVersion, então dá para comparar builds.
//

#import "MetricsCollector.h"

#import <MetricKit/MetricKit.h>
#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <mach/thread_info.h>
#import <os/proc.h>
#import <sys/utsname.h>

#import <monalxmpp/HelperTools.h>
#import <monalxmpp/MLSQLite.h>
#import <monalxmpp/MLXMPPManager.h>

//keep the samples for a while, but never let this grow without a limit
static const NSInteger kMaxSampleAgeDays = 45;
static const NSTimeInterval kSampleIntervalSeconds = 300;

@interface MetricsCollector () <MXMetricManagerSubscriber>
@end

@implementation MetricsCollector
{
    NSTimer* _timer;
    double _lastCPUMilliseconds;
    NSDate* _lastSampleDate;
    NSISO8601DateFormatter* _isoFormatter;
}

+(instancetype) sharedInstance
{
    static MetricsCollector* sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [MetricsCollector new];
    });
    return sharedInstance;
}

+(void) start
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        MetricsCollector* collector = [self sharedInstance];
        [collector prepare];
    });
}

static double _launchStart = 0.0;
static NSMutableDictionary* _launchMarks = nil;
static BOOL _launchFinishedWritten = NO;

+(void) launchStarted
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _launchStart = CACurrentMediaTime();
        _launchMarks = [NSMutableDictionary new];
    });
}

+(void) launchMark:(NSString*) label
{
    if(label == nil || _launchStart <= 0.0 || _launchMarks[label] != nil)
        return;
    _launchMarks[label] = @((CACurrentMediaTime() - _launchStart) * 1000.0);
}

+(void) launchDuration:(NSString*) label milliseconds:(double) milliseconds
{
    if(label == nil || _launchStart <= 0.0)
        return;
    NSNumber* previous = _launchMarks[label];       //keep the worst case: the refresh that took longer
    if(previous == nil || milliseconds > previous.doubleValue)
        _launchMarks[label] = @(milliseconds);
}

+(void) launchFinished
{
    //only writes when both the screen appeared and the list was built, whichever happens last
    if(_launchFinishedWritten || _launchStart <= 0.0 || _launchMarks[@"first_frame"] == nil || _launchMarks[@"chat_list"] == nil)
        return;
    _launchFinishedWritten = YES;
    NSString* directory = [MetricsCollector metricsDirectoryPath];
    if(directory == nil)
        return;
    NSDictionary* info = NSBundle.mainBundle.infoDictionary ?: @{};
    //launch_ms: total, from main() to the screen appearing (what the user waits)
    //app_delegate_ms + list_build_ms: the work we do on the main thread during the launch
    //list_ready_ms: when the list was built (mark); first_frame_ms: when this screen appeared
    NSNumber* appDelegate = _launchMarks[@"app_delegate"] ?: @(0);
    NSNumber* listBuild = _launchMarks[@"list_build"] ?: @(0);
    double total = [_launchMarks[@"first_frame"] doubleValue];
    NSDictionary* launch = @{
        @"build": info[@"CFBundleVersion"] ?: @"?",
        @"short": info[@"CFBundleShortVersionString"] ?: @"?",
        @"ios": [[UIDevice currentDevice] systemVersion] ?: @"?",
        @"model": [[self sharedInstance] deviceModel] ?: @"?",
        @"launch_ms": @(total),
        @"first_frame_ms": @(total),
        @"app_delegate_ms": appDelegate,
        @"list_ready_ms": _launchMarks[@"chat_list"] ?: @(0),
        @"list_build_ms": listBuild,
        @"main_ms": @(appDelegate.doubleValue + listBuild.doubleValue),
        @"cold": @YES,
        @"at": [[[NSISO8601DateFormatter alloc] init] stringFromDate:[NSDate date]],
    };
    NSData* data = [NSJSONSerialization dataWithJSONObject:launch options:0 error:nil];
    if(data == nil)
        return;
    NSDateFormatter* dayFormatter = [NSDateFormatter new];
    dayFormatter.dateFormat = @"yyyy-MM-dd";
    dayFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    dayFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSString* path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"launches-%@.jsonl", [dayFormatter stringFromDate:[NSDate date]]]];
    NSMutableData* line = [data mutableCopy];
    [line appendBytes:"\n" length:1];
    NSFileHandle* handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if(handle == nil)
        [line writeToFile:path atomically:YES];
    else
    {
        @try {
            [handle seekToEndOfFile];
            [handle writeData:line];
            [handle closeFile];
        } @catch(NSException* exception) {
            DDLogError(@"Could not append to the launch file: %@", exception);
        }
    }
    DDLogInfo(@"isaCloud: abertura a frio: total %.0f ms | didFinishLaunching %.0f ms | montar a lista %.0f ms | na main %.0f ms",
        total, appDelegate.doubleValue, listBuild.doubleValue, appDelegate.doubleValue + listBuild.doubleValue);
}

+(void) sampleNow
{
    [[self sharedInstance] writeSample];
}

+(NSString*) metricsDirectoryPath
{
    NSURL* directory = [HelperTools getContainerURLForPathComponents:@[@"metrics"]];
    NSFileManager* fileManager = [NSFileManager defaultManager];
    if(directory != nil && ![fileManager fileExistsAtPath:directory.path])
        [fileManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return directory.path;
}

-(void) prepare
{
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;

    if([NSISO8601DateFormatter class] != nil)
    {
        _isoFormatter = [NSISO8601DateFormatter new];
        _isoFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    }

    //MetricKit: the only sanctioned way of getting CPU, battery and hang data from the OS
    [[MXMetricManager sharedManager] addSubscriber:self];

    //sample on the moments that matter for a resource evaluation
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(writeSample) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(writeSample) name:UIApplicationDidEnterBackgroundNotification object:nil];

    __weak MetricsCollector* weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:kSampleIntervalSeconds repeats:YES block:^(NSTimer* timer) {
        [weakSelf writeSample];
    }];

    [self writeSample];
}

#pragma mark helpers

-(NSString*) isoString:(NSDate*) date
{
    if(date == nil)
        return nil;
    if(_isoFormatter != nil)
        return [_isoFormatter stringFromDate:date];
    return [NSString stringWithFormat:@"%f", date.timeIntervalSince1970];
}

-(NSString*) deviceModel
{
    struct utsname systemInfo;
    if(uname(&systemInfo) != 0)
        return @"unknown";
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding] ?: @"unknown";
}

-(NSString*) thermalStateString
{
    switch(NSProcessInfo.processInfo.thermalState)
    {
        case NSProcessInfoThermalStateNominal: return @"nominal";
        case NSProcessInfoThermalStateFair: return @"fair";
        case NSProcessInfoThermalStateSerious: return @"serious";
        case NSProcessInfoThermalStateCritical: return @"critical";
    }
    return @"unknown";
}

//cumulative CPU time of this process, in milliseconds. Sums every thread (THREAD_BASIC_INFO), which is the portable
//way: task_basic_info returns zero on the simulators and getrusage returns zero on the device.
-(double) cumulativeCPUMilliseconds
{
    thread_act_array_t threads = NULL;
    mach_msg_type_number_t threadCount = 0;
    if(task_threads(mach_task_self(), &threads, &threadCount) != KERN_SUCCESS || threads == NULL)
        return 0;

    double milliseconds = 0;
    for(mach_msg_type_number_t i = 0; i < threadCount; i++)
    {
        thread_basic_info_data_t info;
        mach_msg_type_number_t count = THREAD_BASIC_INFO_COUNT;
        if(thread_info(threads[i], THREAD_BASIC_INFO, (thread_info_t)&info, &count) == KERN_SUCCESS)
            milliseconds += (double)info.user_time.seconds * 1000.0 + (double)info.user_time.microseconds / 1000.0
                          + (double)info.system_time.seconds * 1000.0 + (double)info.system_time.microseconds / 1000.0;
        mach_port_deallocate(mach_task_self(), threads[i]);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)threads, threadCount * sizeof(thread_act_t));
    return milliseconds;
}

-(double) fileSizeInMegabytes:(NSURL*) url
{
    if(url == nil)
        return 0;
    NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil];
    if(attributes == nil)
        return 0;
    return (double)attributes.fileSize / 1048576.0;
}

-(NSDictionary*) currentSample
{
    NSDate* now = [NSDate date];
    double cpuMilliseconds = [self cumulativeCPUMilliseconds];
    double cpuDelta = _lastSampleDate == nil ? 0 : MAX(0.0, cpuMilliseconds - _lastCPUMilliseconds);
    double wallDelta = _lastSampleDate == nil ? 0 : MAX(0.0, [now timeIntervalSinceDate:_lastSampleDate] * 1000.0);

    NSDictionary* info = NSBundle.mainBundle.infoDictionary ?: @{};
    NSNumber* battery = UIDevice.currentDevice.batteryLevel >= 0 ? @(UIDevice.currentDevice.batteryLevel) : nil;
    NSDate* lastAppexStart = [[HelperTools defaultsDB] objectForKey:@"lastAppexStart"];
    NSURL* dbURL = [HelperTools getContainerURLForPathComponents:@[@"sworim.sqlite"]];
    //isaCloud: how much this sample's window had to wait for the database lock (see MLSQLite consumeLockStatistics)
    NSDictionary* lockStats = [MLSQLite consumeLockStatistics];

    NSMutableDictionary* sample = [@{
        @"ts": [self isoString:now],
        @"build": info[@"CFBundleVersion"] ?: @"?",
        @"short": info[@"CFBundleShortVersionString"] ?: @"?",
        @"ios": UIDevice.currentDevice.systemVersion ?: @"?",
        @"model": [self deviceModel],
        @"mem_footprint_mb": @([HelperTools report_memory]),
        @"mem_available_mb": @((double)os_proc_available_memory() / 1048576.0),
        @"cpu_ms": @(cpuDelta),
        @"wall_ms": @(wallDelta),
        @"thermal": [self thermalStateString],
        @"low_power": @(NSProcessInfo.processInfo.isLowPowerModeEnabled),
        @"accounts_idle": @([[MLXMPPManager sharedInstance] allAccountsIdle]),
        @"db_mb": @([self fileSizeInMegabytes:dbURL]),
        @"db_lock_waits": lockStats[@"waits"] ?: @0,
        @"db_lock_max_ms": lockStats[@"max_ms"] ?: @0,
        @"wal_mb": @([self fileSizeInMegabytes:[NSURL fileURLWithPath:[dbURL.path stringByAppendingString:@"-wal"]]]),
    } mutableCopy];
    if(battery != nil)
        sample[@"battery"] = battery;
    if(lastAppexStart != nil)
        sample[@"last_appex_start"] = [self isoString:lastAppexStart];
    return sample;
}

#pragma mark sampling

-(void) writeSample
{
    NSString* directory = [MetricsCollector metricsDirectoryPath];
    if(directory == nil)
        return;

    NSDictionary* sample = [self currentSample];
    _lastCPUMilliseconds = [self cumulativeCPUMilliseconds];
    _lastSampleDate = [NSDate date];

    NSError* error = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:sample options:0 error:&error];
    if(data == nil)
    {
        DDLogError(@"Could not serialize the metrics sample: %@", error);
        return;
    }

    NSDateFormatter* dayFormatter = [NSDateFormatter new];
    dayFormatter.dateFormat = @"yyyy-MM-dd";
    dayFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    dayFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSString* path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"samples-%@.jsonl", [dayFormatter stringFromDate:_lastSampleDate]]];

    NSMutableData* line = [data mutableCopy];
    [line appendBytes:"\n" length:1];
    NSFileHandle* handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if(handle == nil)
        [line writeToFile:path atomically:YES];
    else
    {
        @try {
            [handle seekToEndOfFile];
            [handle writeData:line];
            [handle closeFile];
        } @catch(NSException* exception) {
            DDLogError(@"Could not append to the metrics file: %@", exception);
        }
    }
    [self removeOldFilesInDirectory:directory];
}

-(void) removeOldFilesInDirectory:(NSString*) directory
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSArray<NSString*>* names = [fileManager contentsOfDirectoryAtPath:directory error:nil];
    NSDate* limit = [NSDate dateWithTimeIntervalSinceNow:-kMaxSampleAgeDays * 86400.0];
    for(NSString* name in names)
    {
        NSString* path = [directory stringByAppendingPathComponent:name];
        NSDictionary* attributes = [fileManager attributesOfItemAtPath:path error:nil];
        if(attributes != nil && [attributes.fileCreationDate compare:limit] == NSOrderedAscending)
            [fileManager removeItemAtPath:path error:nil];
    }
}

#pragma mark MetricKit

//MetricKit payloads contain dates, measurements and other objects that NSJSONSerialization can not handle:
//convert everything to strings/numbers, keeping the structure
-(id) jsonSafeObject:(id) object
{
    if(object == nil || [object isKindOfClass:[NSNull class]])
        return [NSNull null];
    if([object isKindOfClass:[NSString class]] || [object isKindOfClass:[NSNumber class]])
        return object;
    if([object isKindOfClass:[NSDate class]])
        return [self isoString:object];
    if([object isKindOfClass:[NSArray class]])
    {
        NSMutableArray* result = [NSMutableArray new];
        for(id item in (NSArray*)object)
            [result addObject:[self jsonSafeObject:item]];
        return result;
    }
    if([object isKindOfClass:[NSDictionary class]])
    {
        NSMutableDictionary* result = [NSMutableDictionary new];
        for(id key in (NSDictionary*)object)
            result[[key description]] = [self jsonSafeObject:((NSDictionary*)object)[key]];
        return result;
    }
    //NSMeasurement, NSUnit and friends
    return [object description];
}

-(void) saveMetricKitPayload:(NSDictionary*) payload kind:(NSString*) kind
{
    NSString* directory = [MetricsCollector metricsDirectoryPath];
    if(directory == nil || payload == nil)
        return;

    NSDictionary* record = @{
        @"kind": kind,
        @"receivedAt": [self isoString:[NSDate date]],
        @"build": NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"] ?: @"?",
        @"payload": [self jsonSafeObject:payload],
    };
    NSError* error = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:record options:0 error:&error];
    if(data == nil)
    {
        DDLogError(@"Could not serialize the MetricKit payload: %@", error);
        return;
    }
    NSDateFormatter* dateFormatter = [NSDateFormatter new];
    dateFormatter.dateFormat = @"yyyy-MM-dd-HHmmss";
    dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    dateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSString* name = [NSString stringWithFormat:@"metrickit-%@-%@.json", kind, [dateFormatter stringFromDate:[NSDate date]]];
    [data writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES];
    DDLogInfo(@"isaCloud: saved MetricKit payload (%@)", kind);
}

-(void) didReceiveMetricPayloads:(NSArray<MXMetricPayload*>* _Nonnull) payloads
{
    for(MXMetricPayload* payload in payloads)
        [self saveMetricKitPayload:payload.dictionaryRepresentation kind:@"metric"];
}

-(void) didReceiveDiagnosticPayloads:(NSArray<MXDiagnosticPayload*>* _Nonnull) payloads
{
    for(MXDiagnosticPayload* payload in payloads)
        [self saveMetricKitPayload:payload.dictionaryRepresentation kind:@"diagnostic"];
}

#pragma mark export

+(NSURL*) exportMetrics
{
    MetricsCollector* collector = [self sharedInstance];
    NSString* directory = [MetricsCollector metricsDirectoryPath];
    if(directory == nil)
        return nil;

    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSMutableArray* samples = [NSMutableArray new];
    NSMutableArray* metrickit = [NSMutableArray new];
    NSMutableArray* launches = [NSMutableArray new];
    for(NSString* name in [fileManager contentsOfDirectoryAtPath:directory error:nil])
    {
        NSString* path = [directory stringByAppendingPathComponent:name];
        if([name hasPrefix:@"samples-"] && [name hasSuffix:@".jsonl"])
        {
            NSString* contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            for(NSString* line in [contents componentsSeparatedByString:@"\n"])
            {
                if(line.length == 0)
                    continue;
                NSData* data = [line dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary* sample = data != nil ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                if([sample isKindOfClass:[NSDictionary class]])
                    [samples addObject:sample];
            }
        }
        else if([name hasPrefix:@"launches-"] && [name hasSuffix:@".jsonl"])
        {
            NSString* contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            for(NSString* line in [contents componentsSeparatedByString:@"\n"])
            {
                if(line.length == 0)
                    continue;
                NSData* data = [line dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary* launch = data != nil ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                if([launch isKindOfClass:[NSDictionary class]])
                    [launches addObject:launch];
            }
        }
        else if([name hasPrefix:@"metrickit-"] && [name hasSuffix:@".json"])
        {
            NSData* data = [NSData dataWithContentsOfFile:path];
            NSDictionary* record = data != nil ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if([record isKindOfClass:[NSDictionary class]])
                [metrickit addObject:record];
        }
    }

    NSDictionary* info = NSBundle.mainBundle.infoDictionary ?: @{};
    NSDictionary* root = @{
        @"exportedAt": [collector isoString:[NSDate date]],
        @"build": info[@"CFBundleVersion"] ?: @"?",
        @"samples": samples,
        @"launches": launches,
        @"metrickit": metrickit,
    };
    NSError* error = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:&error];
    if(data == nil)
    {
        DDLogError(@"Could not build the metrics export: %@", error);
        return nil;
    }

    NSDateFormatter* nameFormatter = [NSDateFormatter new];
    nameFormatter.dateFormat = @"yyyy-MM-dd-HHmmss";
    nameFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSString* name = [NSString stringWithFormat:@"isaCloud-metrics-%@-%@.json", info[@"CFBundleVersion"] ?: @"?", [nameFormatter stringFromDate:[NSDate date]]];
    NSURL* url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    if(![data writeToURL:url atomically:YES])
        return nil;
    DDLogInfo(@"isaCloud: exported %lu samples and %lu MetricKit payloads to %@", (unsigned long)samples.count, (unsigned long)metrickit.count, url.path);
    return url;
}

@end
