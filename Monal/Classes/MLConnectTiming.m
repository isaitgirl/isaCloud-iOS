//
//  MLConnectTiming.m
//  monalxmpp
//
//  isaCloud: tempo de cada tentativa de conexão por conta (ver MLConnectTiming.h e docs/decisoes.md).
//  Os tempos são em ms desde o início da tentativa; o registro sai no fim, em background, sem bloquear
//  a fila de recebimento. Não entra JID, usuário ou senha: só o domínio do servidor.
//

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <sys/utsname.h>

#import <monalxmpp/MLConnectTiming.h>
#import <monalxmpp/HelperTools.h>

static double _launchStart = 0.0;
static NSMutableDictionary* _reasons = nil;             //accountID -> reason of the next attempt
static NSMutableDictionary* _attemptCounts = nil;       //accountID -> number of attempts since the process started
static dispatch_queue_t _writeQueue = nil;              //serial: two accounts finishing together must not write the same file at once

@implementation MLConnectTiming
{
    double _start;                                      //CACurrentMediaTime() when the attempt began
    NSString* _reason;
    NSNumber* _attempt;
    NSString* _server;
    BOOL _background;
    NSMutableDictionary* _marks;                        //stage -> ms since _start
    BOOL _finished;
}

+(void) initialize
{
    if(self == [MLConnectTiming class])
    {
        _reasons = [NSMutableDictionary new];
        _attemptCounts = [NSMutableDictionary new];
        _writeQueue = dispatch_queue_create("im.isacloud.connect-timing.write", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    }
}

+(void) setLaunchStart:(double) launchStart
{
    @synchronized(self) {
        _launchStart = launchStart;
    }
}

+(void) setReason:(NSString*) reason forAccount:(NSNumber*) accountID
{
    if(reason == nil || accountID == nil)
        return;
    @synchronized(self) {
        _reasons[accountID.stringValue] = reason;
    }
}

+(instancetype) beginForAccount:(NSNumber*) accountID server:(NSString*) server background:(BOOL) background
{
    MLConnectTiming* timing = [MLConnectTiming new];
    timing->_marks = [NSMutableDictionary new];
    //the app extension also connects, but its attempts are not measured (the app writes the record of the attempts it makes)
    if([HelperTools isAppExtension])
    {
        timing->_finished = YES;
        return timing;
    }
    NSString* key = accountID.stringValue ?: @"?";
    @synchronized(self) {
        timing->_reason = _reasons[key] ?: @"reconnect";
        [_reasons removeObjectForKey:key];
        NSNumber* count = @([_attemptCounts[key] integerValue] + 1);
        _attemptCounts[key] = count;
        timing->_attempt = count;
    }
    timing->_start = CACurrentMediaTime();
    timing->_server = server ?: @"?";
    timing->_background = background;
    return timing;
}

-(void) mark:(NSString*) name
{
    @synchronized(self) {
        if(_finished || name == nil || _marks[name] != nil)
            return;
        //one decimal is enough (0.1 ms) and keeps the lines short
        _marks[name] = @(round((CACurrentMediaTime() - _start) * 10000.0) / 10.0);
    }
}

-(void) finishWithOutcome:(NSString*) outcome
{
    NSDictionary* record = nil;
    @synchronized(self) {
        if(_finished)
            return;
        _finished = YES;
        record = [self recordWithOutcome:outcome];
    }
    DDLogInfo(@"isaCloud: conexão (%@) terminou com %@: ociosa em %.0f ms (dns %.0f, tls %.0f, login %.0f, catchup %.0f)",
        record[@"reason"], record[@"outcome"], [record[@"idle_ms"] doubleValue], [record[@"dns_ms"] doubleValue],
        [record[@"tls_ms"] doubleValue], [record[@"login_ms"] doubleValue], [record[@"catchup_ms"] doubleValue]);
    //the file write runs in the background, away from the receive queue and from the database transactions;
    //the queue is serial so two accounts finishing together do not append to the same file at once
    dispatch_async(_writeQueue, ^{
        [MLConnectTiming appendRecord:record];
    });
}

//called with the lock held
-(NSDictionary*) recordWithOutcome:(NSString*) outcome
{
    NSDictionary* info = NSBundle.mainBundle.infoDictionary ?: @{};
    NSISO8601DateFormatter* isoFormatter = [[NSISO8601DateFormatter alloc] init];
    NSMutableDictionary* record = [@{
        @"kind": @"connect",
        @"reason": _reason,
        @"attempt": _attempt,
        @"server": _server,
        @"background": _background ? @YES : @NO,     //explicit booleans: @(BOOL) serializes as 0/1
        @"outcome": outcome ?: @"?",
        @"resumed": _marks[@"resumed"] != nil ? @YES : @NO,
        @"dns_done": _marks[@"dns"] != nil ? @YES : @NO,
        @"dns_ms": _marks[@"dns"] ?: @(0),
        @"build": info[@"CFBundleVersion"] ?: @"?",
        @"short": info[@"CFBundleShortVersionString"] ?: @"?",
        @"ios": [[UIDevice currentDevice] systemVersion] ?: @"?",
        @"model": [MLConnectTiming deviceModel],
        @"at": [isoFormatter stringFromDate:[NSDate date]],
    } mutableCopy];
    //when the launch reference is unknown (should not happen) the field is left out
    if(_launchStart > 0.0)
        record[@"since_launch_ms"] = @(round((_start - _launchStart) * 10000.0) / 10.0);
    //only the stages that happened, as <stage>_ms
    for(NSString* stage in @[@"tcp", @"tls", @"login", @"bound", @"catchup", @"idle"])
        if(_marks[stage] != nil)
            record[[stage stringByAppendingString:@"_ms"]] = _marks[stage];
    return record;
}

+(NSString*) deviceModel
{
    struct utsname systemInfo;
    if(uname(&systemInfo) != 0)
        return @"unknown";
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding] ?: @"unknown";
}

+(void) appendRecord:(NSDictionary*) record
{
    //same layout as launches-*.jsonl: one JSON per line, one file per day (UTC), under <grupo>/Library/metrics
    NSData* data = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    NSURL* directory = [HelperTools getContainerURLForPathComponents:@[@"Library", @"metrics"]];
    if(data == nil || directory == nil)
        return;
    [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSDateFormatter* dayFormatter = [NSDateFormatter new];
    dayFormatter.dateFormat = @"yyyy-MM-dd";
    dayFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    dayFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSString* path = [directory.path stringByAppendingPathComponent:[NSString stringWithFormat:@"connects-%@.jsonl", [dayFormatter stringFromDate:[NSDate date]]]];
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
            DDLogError(@"Could not append to the connect file: %@", exception);
        }
    }
}

@end
