//
//  MLLongLog.m
//  monalxmpp
//
//  isaCloud: log longo opcional (ver MLLongLog.h). Filtra o que já passa pelo DDLog: não mexe no rawlog nem nas
//  chamadas existentes. Regras: erro e aviso sempre passam pelo filtro de texto; informação passa, exceto o ruído
//  da lista de descarte; depuração e verbose passam só se baterem na lista de manter; cada mensagem tem limite de
//  taxa por texto; uma linha-resumo a cada 10 s conta o que foi descartado de stanzas e de gravações no banco.
//

#import <UIKit/UIKit.h>
#import <math.h>
#import <stdatomic.h>
#import <os/lock.h>
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/MLLongLog.h>

static NSString* const kLongLogEnabledKey = @"IsaCloudLogLongo";
static const NSUInteger kLongLogMaxLineLength = 1500;
static const NSUInteger kLongLogMaxLinesPerSecondPerKey = 40;
static const NSTimeInterval kLongLogSummaryInterval = 10.0;
static const NSUInteger kLongLogKeyLength = 40;

//strong reference: the logger must live as long as the process
static DDFileLogger* _longLogFileLogger = nil;
//counters of the summary line (lines dropped since the last summary)
static _Atomic(uint64_t) _longLogStanzasDropped = 0;
static _Atomic(uint64_t) _longLogPersistDropped = 0;

//noise that is dropped at every level (INFO included); matched literally
static NSArray<NSString*>* longLogDropLiterals(void)
{
    return @[
        @"transaction trigger", @"Would now call realPersistState", @"Inside transaction end trigger",
        @"Starting transaction for", @"Started transaction for", @"Ending transaction for", @"Ended transaction for",
        @"Freezing sendQueue", @"sendQueue is frozen", @"Queueing notification", @"Notifications in queue",
        @"Done flushing", @"Flushing queue", @"Promoting all", @"Adding participant", @"Got muc presence",
        @"Publishing participants", @"Removing participant", @"Adding member", @"Publishing new memberslist",
        @"KVOObserver", @"objectWillChange", @"Singleton cache", @"Handling global refresh", @"Deallocating",
        @"Done deallocating", @"nw_connection", @"Incoming data handler", @"has bytes to read", @"has space to write",
        @"has event", @"XML parser returned", @"_outputQueue", @"empty message", @"hot path", @"Write completed",
        @"iterating", @"realPersistState before", @"realPersistState after", @"realPersistState is now",
        @"Synchronously handling next stanza", @"Parse finished for new", @"DISPATCHING", @"Calling handler",
        @"iqHandlers", @"idle state notification", @"LastInteraction", @"lastInteraction",
        @"Triggering db checkpoint", @"Checkpointing database", @"Getting trust level", @"Prepending block",
        @"Block with id", @"Calling block", @"Looping to next", @"processViewQueue", @"Starting timer",
        @"Canceling timer", @"Could not invalidate",
    ];
}

//debug and verbose lines that are kept (regular expression, one alternation)
static NSString* const kLongLogKeepPattern = @"App now|App started|App launching|Starting: |background task|UIKit background|Posting kMonal|kMonal(Will|Is)|Freezing account|Unfreezing|Reloading UNfrozen|Parse queue is|Locking process|Unlocking process|Suspending logger|_shutdownPending|incomingWakeup|Remote .* running|IPC|CHANGED TO|ALL ACCOUNTS IDLE|checking if background|disconnect|Disconnect|reconnect|Reconnect|connecting account|Creating account|bind|resum|Resum|smacks|nw_path|path monitor|Connection (state|failed|closed)|stream error|TLS|SASL|login|catchup|catch-up|mam catchups|handler triggered|Invalidating iq|Sleeping|Write transaction|Database opened|Closing database|Chekpointing returned|slow persistState|Database version|migration|Device id|isaCloud (SPIN|C20|C30|C32|LONGLOG)|push token|Current notification settings|Handling push";

//one line of the storm limiter: messages per key in the current second
@interface MLLongLogRate : NSObject
@property (nonatomic) int64_t second;
@property (nonatomic) NSUInteger count;
@property (nonatomic) NSUInteger suppressed;
@end

@implementation MLLongLogRate
@end

@interface MLLongLogFormatter : NSObject <DDLogFormatter>
-(instancetype) initWithProcess:(NSString*) process;
@end

@implementation MLLongLogFormatter
{
    NSString* _process;
    NSDateFormatter* _dateFormatter;
    NSRegularExpression* _dropRegex;
    NSRegularExpression* _keepRegex;
    NSMutableDictionary<NSString*, MLLongLogRate*>* _rates;
    NSTimeInterval _lastCleanup;
    NSTimeInterval _lastSummary;
    uint64_t _linesKept;
    uint64_t _linesDropped;
    os_unfair_lock _lock;
}

-(instancetype) initWithProcess:(NSString*) process
{
    self = [super init];
    _process = process;
    _dateFormatter = [NSDateFormatter new];
    _dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    _dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";

    NSMutableArray<NSString*>* escaped = [NSMutableArray new];
    for(NSString* literal in longLogDropLiterals())
        [escaped addObject:[NSRegularExpression escapedPatternForString:literal]];
    NSError* error = nil;
    _dropRegex = [NSRegularExpression regularExpressionWithPattern:[escaped componentsJoinedByString:@"|"] options:0 error:&error];
    if(error != nil)
        DDLogError(@"isaCloud LONGLOG: drop pattern invalid: %@", error);
    _keepRegex = [NSRegularExpression regularExpressionWithPattern:kLongLogKeepPattern options:0 error:&error];
    if(error != nil)
        DDLogError(@"isaCloud LONGLOG: keep pattern invalid: %@", error);

    _rates = [NSMutableDictionary new];
    _lastSummary = [NSDate date].timeIntervalSince1970;
    _lastCleanup = _lastSummary;
    _lock = OS_UNFAIR_LOCK_INIT;
    return self;
}

-(BOOL) matches:(NSRegularExpression*) regex text:(NSString*) text
{
    if(regex == nil)
        return NO;
    return [regex numberOfMatchesInString:text options:0 range:NSMakeRange(0, text.length)] > 0;
}

-(NSString*) timestampString:(NSDate*) date
{
    return [_dateFormatter stringFromDate:date];
}

-(NSString* _Nullable) formatLogMessage:(DDLogMessage*) logMessage
{
    NSString* text = logMessage.message ?: @"";
    NSDate* timestamp = logMessage.timestamp ?: [NSDate date];
    NSTimeInterval now = timestamp.timeIntervalSince1970;
    NSUInteger flag = logMessage.flag;
    NSMutableArray<NSString*>* lines = [NSMutableArray new];

    os_unfair_lock_lock(&_lock);

    //summary line, at most every 10 s (checked when a message arrives, no timer)
    if(now - _lastSummary >= kLongLogSummaryInterval)
    {
        _lastSummary = now;
        uint64_t stanzas = atomic_exchange(&_longLogStanzasDropped, 0);
        uint64_t persist = atomic_exchange(&_longLogPersistDropped, 0);
        [lines addObject:[NSString stringWithFormat:@"%@ I [%@] LONGLOG 10s: stanzas_parsed=%llu persist_triggers=%llu lines_dropped=%llu lines_kept=%llu",
            [self timestampString:timestamp], _process, (unsigned long long)stanzas, (unsigned long long)persist,
            (unsigned long long)_linesDropped, (unsigned long long)_linesKept]];
    }

    //text rules: flag 1 is error, 2 is warning, 4 info, 8 debug, 16 verbose
    BOOL keep;
    if(flag == 1 || flag == 2)
        keep = YES;
    else if([self matches:_dropRegex text:text])
    {
        keep = NO;
        if([text containsString:@"Parse finished for new"])
            atomic_fetch_add(&_longLogStanzasDropped, 1);
        if([text containsString:@"Inside transaction end trigger"])
            atomic_fetch_add(&_longLogPersistDropped, 1);
    }
    else if(flag == 4)
        keep = YES;
    else
        keep = [self matches:_keepRegex text:text];

    //storm limiter: at most 40 lines of the same message per second (errors are never limited)
    if(keep && flag != 1)
    {
        NSString* key = logMessage.messageFormat.length > 0 ? logMessage.messageFormat : [text substringToIndex:MIN(kLongLogKeyLength, text.length)];
        int64_t second = (int64_t)floor(now);
        MLLongLogRate* rate = _rates[key];
        if(rate == nil)
        {
            rate = [MLLongLogRate new];
            rate.second = second;
            _rates[key] = rate;
        }
        if(rate.second != second)
        {
            if(rate.suppressed > 0)
                [lines addObject:[NSString stringWithFormat:@"%@ I [%@] … [suppressed %lu lines of \"%@\"]",
                    [self timestampString:timestamp], _process, (unsigned long)rate.suppressed, key]];
            rate.second = second;
            rate.count = 0;
            rate.suppressed = 0;
        }
        if(rate.count >= kLongLogMaxLinesPerSecondPerKey)
        {
            rate.suppressed++;
            keep = NO;
        }
        else
            rate.count++;

        //forget keys that were not seen for a minute, every five minutes
        if(now - _lastCleanup > 300)
        {
            _lastCleanup = now;
            NSMutableArray<NSString*>* stale = [NSMutableArray new];
            for(NSString* staleKey in _rates)
                if(_rates[staleKey].second < second - 60)
                    [stale addObject:staleKey];
            [_rates removeObjectsForKeys:stale];
        }
    }

    if(!keep)
    {
        _linesDropped++;
        os_unfair_lock_unlock(&_lock);
        return lines.count > 0 ? [lines componentsJoinedByString:@"\n"] : nil;
    }

    //plain text line: time, level, process, queue, class, message (newlines and long text shortened)
    NSString* level = @"?";
    if(flag == 1) level = @"E";
    else if(flag == 2) level = @"W";
    else if(flag == 4) level = @"I";
    else if(flag == 8) level = @"D";
    else if(flag == 16) level = @"V";
    NSString* body = [text stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    body = [body stringByReplacingOccurrencesOfString:@"\n" withString:@" ⏎ "];
    if(body.length > kLongLogMaxLineLength)
    {
        NSUInteger cut = [body rangeOfComposedCharacterSequenceAtIndex:kLongLogMaxLineLength].location;
        NSUInteger extra = body.length - cut;
        body = [[body substringToIndex:cut] stringByAppendingFormat:@"…[+%lu]", (unsigned long)extra];
    }
    NSString* queue = logMessage.queueLabel ?: @"-";
    if(queue.length > 28)
        queue = [queue substringFromIndex:queue.length - 28];
    [lines addObject:[NSString stringWithFormat:@"%@ %@ [%@] [%@] [%@] %@",
        [self timestampString:timestamp], level, _process, queue, logMessage.fileName ?: @"-", body]];
    _linesKept++;

    os_unfair_lock_unlock(&_lock);
    return [lines componentsJoinedByString:@"\n"];
}

@end

@implementation MLLongLog

+(BOOL) isEnabled
{
    return [[HelperTools defaultsDB] boolForKey:kLongLogEnabledKey];
}

+(void) startIfEnabled
{
    if(![self isEnabled])
        return;
    if(_longLogFileLogger != nil)
        return;

    NSString* subdir = [HelperTools isAppExtension] ? @"appex" : @"app";
    NSURL* dirURL = [HelperTools getContainerURLForPathComponents:@[@"Library", @"logs-long", subdir]];
    NSError* error = nil;
    if(![[NSFileManager defaultManager] createDirectoryAtURL:dirURL withIntermediateDirectories:YES attributes:nil error:&error])
    {
        DDLogError(@"isaCloud LONGLOG: could not create the directory %@: %@", dirURL.path, error);
        return;
    }

    DDLogFileManagerDefault* manager = [[DDLogFileManagerDefault alloc] initWithLogsDirectory:dirURL.path defaultFileProtectionLevel:NSFileProtectionCompleteUntilFirstUserAuthentication];
    manager.maximumNumberOfLogFiles = 40;
    manager.logFilesDiskQuota = (unsigned long long)1024 * 1024 * 1024;

    DDFileLogger* logger = [[DDFileLogger alloc] initWithLogFileManager:manager];
    logger.maximumFileSize = (unsigned long long)25 * 1024 * 1024;
    logger.rollingFrequency = 60 * 60 * 24;
    logger.doNotReuseLogFiles = NO;
    logger.logFormatter = [[MLLongLogFormatter alloc] initWithProcess:subdir];
    [DDLog addLogger:logger];
    _longLogFileLogger = logger;

    DDLogInfo(@"isaCloud LONGLOG: enabled, dir=%@", dirURL.path);
}

+(NSURL* _Nullable) exportForHours:(NSInteger) hours
{
    NSFileManager* fm = [NSFileManager defaultManager];
    NSTimeInterval since = [NSDate date].timeIntervalSince1970 - (NSTimeInterval)hours * 3600.0;
    NSMutableArray<NSDictionary*>* picked = [NSMutableArray new];
    NSMutableDictionary<NSString*, NSNumber*>* counts = [NSMutableDictionary new];

    //per directory: the files written in the period, plus the newest one of the directory
    for(NSString* subdir in @[@"app", @"appex"])
    {
        NSURL* dirURL = [HelperTools getContainerURLForPathComponents:@[@"Library", @"logs-long", subdir]];
        NSArray<NSURL*>* entries = [fm contentsOfDirectoryAtURL:dirURL includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:nil];
        NSMutableArray<NSDictionary*>* logs = [NSMutableArray new];
        for(NSURL* url in entries)
        {
            if(![url.pathExtension isEqualToString:@"log"])
                continue;
            NSDate* date = nil;
            [url getResourceValue:&date forKey:NSURLContentModificationDateKey error:nil];
            if(date == nil)
                continue;
            [logs addObject:@{@"url": url, @"date": date}];
        }
        //newest first
        [logs sortUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
            return [b[@"date"] compare:a[@"date"]];
        }];
        NSUInteger n = 0;
        for(NSUInteger i = 0; i < logs.count; i++)
        {
            NSDate* date = logs[i][@"date"];
            if(i > 0 && date.timeIntervalSince1970 < since)
                break;
            [picked addObject:@{@"url": logs[i][@"url"], @"date": date}];
            n++;
        }
        counts[subdir] = @(n);
    }
    if(picked.count == 0)
        return nil;

    //oldest first, so the export reads in time order
    [picked sortUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
        return [a[@"date"] compare:b[@"date"]];
    }];

    NSString* build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?";
    NSDateFormatter* stampFormatter = [NSDateFormatter new];
    stampFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    stampFormatter.dateFormat = @"yyyyMMdd-HHmm";
    NSString* name = [NSString stringWithFormat:@"isacloud-log-longo-%@-%@.log", build, [stampFormatter stringFromDate:[NSDate date]]];
    NSString* plainPath = [NSTemporaryDirectory() stringByAppendingPathComponent:name];

    FILE* output = fopen(plainPath.fileSystemRepresentation, "wb");
    if(output == NULL)
    {
        DDLogError(@"isaCloud LONGLOG: could not open the export file %@", plainPath);
        return nil;
    }
    NSString* header = [NSString stringWithFormat:@"# isaCloud long log, build %@, %@, iOS %@, last %ld h, files app=%@ appex=%@\n",
        build, [[UIDevice currentDevice] model], [[UIDevice currentDevice] systemVersion], (long)hours, counts[@"app"], counts[@"appex"]];
    fputs(header.UTF8String, output);

    //copied in 1 MB chunks, never a whole file in memory
    size_t chunkSize = 1024 * 1024;
    uint8_t* buffer = malloc(chunkSize);
    for(NSDictionary* entry in picked)
    {
        NSURL* url = entry[@"url"];
        FILE* input = fopen(url.path.fileSystemRepresentation, "rb");
        if(input == NULL)
            continue;
        size_t chunk = 0;
        while((chunk = fread(buffer, 1, chunkSize, input)) > 0)
            fwrite(buffer, 1, chunk, output);
        fclose(input);
    }
    free(buffer);
    fclose(output);

    NSURL* gzipped = [HelperTools compressFileAtPath:plainPath withLevel:9];
    [fm removeItemAtPath:plainPath error:nil];
    return gzipped;
}

@end
