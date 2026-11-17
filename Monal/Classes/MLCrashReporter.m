//
//  MLCrashReporter.m
//  Monal
//
//  Created by admin on 21.06.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/DataLayer.h>
#import <monalxmpp/MLContact.h>
#import <monalxmpp/MLMessage.h>
#import <monalxmpp/MLFileTransfer.h>
#import <monalxmpp/MLOMEMO.h>
#import <monalxmpp/MLXMPPManager.h>
#import <monalxmpp/xmpp.h>
#import "MonalAppDelegate.h"
#import "MLCrashReporter.h"

@import KSCrashCore;
@import KSCrashDemangleFilter;
@import KSCrashFilters;

#define PART_SEPARATOR_FORMAT "\n\n-------- d049d576-9bf0-47dd-839f-dee6b07c1df9 -------- %@ -------- d049d576-9bf0-47dd-839f-dee6b07c1df9 --------\n\n"

//isaCloud: the account that receives the crash reports (it only receives them, nobody answers there)
#define CRASH_REPORTS_JID @"reports@isacloud.im"
#define CRASH_GUIDE_ROOM_JID @"guiaxmpp@conference.isacloud.cc"
//isaCloud: the outbox keeps at most this many reports, and no report older than this
#define CRASH_OUTBOX_MAX_FILES 5
#define CRASH_OUTBOX_MAX_AGE (7.0 * 24 * 60 * 60)
//isaCloud: the time given to a connection, to the devicelist and bundles of the reports account, and to the upload and send of one file
#define CRASH_ACCOUNT_WAIT 15.0
#define CRASH_OMEMO_WAIT 30.0
#define CRASH_SEND_WAIT 60.0

@interface KSCrashReportFilterMLAlert : NSObject <KSCrashReportFilter>
-(instancetype) initWithTitle:(NSString*) title message:(NSString*) message yesAnswer:(NSString*) yesAnswer noAnswer:(NSString*) noAnswer;
@end

@interface KSCrashReportFilterMLEmpty: NSObject <KSCrashReportFilter>
@end

@interface KSCrashReportFilterMLAddAuxInfo : NSObject <KSCrashReportFilter>
@end

@interface KSCrashReportFilterMLAddMLLogfile : NSObject <KSCrashReportFilter>
@end

@interface KSCrashReportFilterMLAddProfraw : NSObject <KSCrashReportFilter>
@end

//isaCloud: keeps the date, version and build of each report, because the later filters turn the reports into compressed data
@interface KSCrashReportFilterMLCaptureMetadata : NSObject <KSCrashReportFilter>
@end


@interface MLCrashReporter() <KSCrashReportFilter>
@end


//isaCloud: metadata of the reports of the running pipeline (same order as the reports) and the outbox files being sent now (by name)
static NSArray<NSDictionary*>* crashReportMetadata = nil;
static NSMutableSet<NSString*>* crashOutboxInFlight = nil;


@implementation MLCrashReporter

+(void) reportPendingCrashes
{
    //isaCloud: reports saved by an earlier launch go out first (the person already said yes to them)
    [self processCrashOutbox];

    //send out pending KSCrash reports
    //isaCloud: own alert (the KSCrash one cannot color its buttons): "Send" in the isaCloud pink and bold, "Not now" in grey
    id<KSCrashReportFilter> alertFilter = [[KSCrashReportFilterMLAlert alloc]
        initWithTitle:NSLocalizedString(@"🥺 The app closed unexpectedly last time", @"Crash reporting: title of the question about sending a crash report")
        message:NSLocalizedString(@"Send the diagnostic report to help us fix this?\nWe only use it to investigate and discard the file right after.", @"Crash reporting: text of the question about sending a crash report")
        yesAnswer:NSLocalizedString(@"Send", @"Crash reporting: button that sends the crash report")
        noAnswer:NSLocalizedString(@"Not now", @"Crash reporting: button that does not send the crash report now")
    ];
    id<KSCrashReportFilter> dummyFilter = [KSCrashReportFilterMLEmpty new];
    NSString* dummyFilterName = @"dummy not printed";
    id<KSCrashReportFilter> auxInfoFilter = [KSCrashReportFilterMLAddAuxInfo new];
    NSString* auxInfoName = @"AUX Info (*.txt)";
    id<KSCrashReportFilter> appleFilter = [[KSCrashReportFilterAppleFmt alloc] initWithReportStyle:KSAppleReportStyleSymbolicatedSideBySide];
    NSString* appleName = @"Apple Report (*.crash)";
    id<KSCrashReportFilter> jsonFilter = [[KSCrashReportFilterPipeline alloc] initWithFilters:@[
        [[KSCrashReportFilterJSONEncode alloc] initWithOptions:KSJSONEncodeOptionSorted | KSJSONEncodeOptionPretty],
        [KSCrashReportFilterStringify new]
    ]];
    NSString* jsonName = @"JSON Report (*.json)";
    id<KSCrashReportFilter> logfileFilter = [KSCrashReportFilterMLAddMLLogfile new];
    NSString* logfileName = @"Logfile (*.rawlog.gz)";
    id<KSCrashReportFilter> profrawFilter = [KSCrashReportFilterMLAddProfraw new];
    NSString* profrawName = @"Profile (*.profraw)";
    KSCrash.sharedInstance.reportStore.sink = [[KSCrashReportFilterPipeline alloc] initWithFilters:@[
        alertFilter,
        [KSCrashReportFilterMLCaptureMetadata new],
        [KSCrashReportFilterDemangle new],
        [KSCrashReportFilterDoctor new],
        [[KSCrashReportFilterCombine alloc] initWithFilters:@{
            dummyFilterName: dummyFilter,       //this dummy is needed to make the filter framework print the title of our aux data
            auxInfoName: auxInfoFilter,
            appleName: appleFilter,
            jsonName: jsonFilter,
            logfileName: logfileFilter,
            profrawName: profrawFilter,
        }],
        [[KSCrashReportFilterConcatenate alloc] initWithSeparatorFmt:@PART_SEPARATOR_FORMAT keys:@[
            dummyFilterName,
            auxInfoName,
            appleName,
            jsonName,
            logfileName,
            profrawName,
        ]],
        [KSCrashReportFilterStringToData new],
        [[KSCrashReportFilterGZipCompress alloc] initWithCompressionLevel:KSCrashReportCompressionLevelDefault],
        [self new],                             //add this class as the last filter: it saves the reports and sends them to reports@
    ]];
    DDLogVerbose(@"Trying to send crash reports...");
    [KSCrash.sharedInstance.reportStore sendAllReportsWithCompletion:^(NSArray* reports, NSError* error) {
        if(error == nil)
            DDLogWarn(@"Sent %lu reports", [reports count]);
        else
            DDLogError(@"Failed to send reports: %@", error);
    }];
}

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
#if TARGET_OS_SIMULATOR
    //isaCloud: on the simulator the reports are also kept in the container of the app, for tests
    u_int32_t runid_raw = arc4random();
    NSString* runid = [HelperTools hexadecimalString:[NSData dataWithBytes:&runid_raw length:sizeof(runid_raw)]];
    int i = 1;
    for(id report in reports)
    {
        NSData* data = [MLCrashReporter dataOfReport:report];
        if(data == nil)
            DDLogError(@"Report was of unsupported data type %@", [report class]);
        else
        {
            NSString* path = [[HelperTools getContainerURLForPathComponents:@[[NSString stringWithFormat:@"CrashReport-%@-%d.mcrash.gz", runid, i]]] path];
            DDLogWarn(@"Writing report %d to file: %@", i, path);
            [data writeToFile:path atomically:YES];
        }
        i++;
    }
#endif

    //isaCloud: the reports go to the outbox first. Only when they are safely there KSCrash may delete its copies
    NSArray<NSURL*>* files = [MLCrashReporter saveReportsToOutbox:reports];
    if(files == nil)
    {
        //nothing was lost: KSCrash keeps its copies and asks again on the next launch
        DDLogError(@"Could not save the crash reports to the outbox");
        kscrash_callCompletion(onCompletion, reports,
                                 [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                     code:0
                                              description:@"Crash report outbox not writable"]);
        return;
    }
    kscrash_callCompletion(onCompletion, reports, nil);

    [MLCrashReporter sendReportFiles:files allowShare:YES];
}

#pragma mark - isaCloud: outbox

+(NSData* _Nullable) dataOfReport:(id) report
{
    if([report isKindOfClass:[NSData class]])
        return report;
    if([report isKindOfClass:[KSCrashReportData class]] && [[report untypedValue] isKindOfClass:[NSData class]])
        return [report untypedValue];
    return nil;
}

+(NSURL*) outboxURL
{
    NSURL* url = [HelperTools getContainerURLForPathComponents:@[@"crash-outbox"]];
    [[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
    return url;
}

//isaCloud: the date, version and build of the crash are in the file name (crash_<epoch>_<version>_<build>_<uuid>.mcrash.gz), so the outbox needs no other file
+(NSString*) safeNamePart:(NSString* _Nullable) part
{
    if(![part isKindOfClass:[NSString class]] || part.length == 0)
        return @"unknown";
    NSMutableCharacterSet* allowed = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowed addCharactersInString:@".-"];
    NSString* safe = [[part componentsSeparatedByCharactersInSet:[allowed invertedSet]] componentsJoinedByString:@"-"];
    return safe.length > 0 ? safe : @"unknown";
}

+(NSDictionary* _Nullable) metadataOfReportAtIndex:(NSUInteger) index
{
    @synchronized([MLCrashReporter class]) {
        return index < crashReportMetadata.count ? crashReportMetadata[index] : nil;
    }
}

//returns the outbox files of the reports, or nil if one of them could not be written (the ones written are removed again)
+(NSArray<NSURL*>* _Nullable) saveReportsToOutbox:(NSArray*) reports
{
    NSFileManager* fm = [NSFileManager defaultManager];
    NSMutableArray<NSURL*>* files = [NSMutableArray new];
    NSUInteger index = 0;
    for(id report in reports)
    {
        NSData* data = [self dataOfReport:report];
        NSDictionary* meta = [self metadataOfReportAtIndex:index++];
        NSDate* date = meta[@"date"] ?: [NSDate date];
        NSString* name = [NSString stringWithFormat:@"crash_%.0f_%@_%@_%@.mcrash.gz",
            [date timeIntervalSince1970], [self safeNamePart:meta[@"version"]], [self safeNamePart:meta[@"build"]], [[NSUUID UUID] UUIDString]];
        NSURL* file = [[self outboxURL] URLByAppendingPathComponent:name];
        NSError* error = nil;
        if(data == nil || ![data writeToURL:file options:NSDataWritingAtomic error:&error])
        {
            DDLogError(@"Could not save crash report %@ to the outbox: %@", name, error);
            for(NSURL* written in files)
                [fm removeItemAtURL:written error:nil];
            return nil;
        }
        [files addObject:file];
    }
    [self trimOutbox];
    return files;
}

+(NSArray<NSURL*>*) outboxFiles
{
    NSArray<NSURL*>* all = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[self outboxURL] includingPropertiesForKeys:nil options:0 error:nil] ?: @[];
    NSMutableArray<NSURL*>* files = [NSMutableArray new];
    for(NSURL* file in all)
        if([file.lastPathComponent hasPrefix:@"crash_"] && [file.lastPathComponent hasSuffix:@".mcrash.gz"])
            [files addObject:file];
    //newest first
    [files sortUsingComparator:^NSComparisonResult(NSURL* a, NSURL* b) {
        return [[self dateOfOutboxFile:b] compare:[self dateOfOutboxFile:a]];
    }];
    return files;
}

+(NSArray<NSString*>*) partsOfOutboxFile:(NSURL*) file
{
    return [file.lastPathComponent componentsSeparatedByString:@"_"];
}

//a temporary copy named "keepname.ios-b117-20261117-144750Z.mcrash.gz" (UTC) (see MLFiletransfer, internalTmpFileUploadHandler); nil if it fails
+(NSURL* _Nullable) copyWithReadableNameOfOutboxFile:(NSURL*) file
{
    NSArray<NSString*>* parts = [self partsOfOutboxFile:file];
    if(parts.count < 4)
        return nil;
    NSDateFormatter* formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    //always UTC (marked with "Z"): the people sending reports are in many time zones
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSString* name = [NSString stringWithFormat:@"keepname.ios-b%@-%@Z.mcrash.gz", parts[3], [formatter stringFromDate:[self dateOfOutboxFile:file]]];
    NSURL* folder = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL* copy = [folder URLByAppendingPathComponent:name];
    [[NSFileManager defaultManager] removeItemAtURL:copy error:nil];
    NSError* error = nil;
    if(![[NSFileManager defaultManager] copyItemAtURL:file toURL:copy error:&error])
    {
        DDLogWarn(@"Could not copy the crash report with a readable name: %@", error);
        return nil;
    }
    return copy;
}

+(NSDate*) dateOfOutboxFile:(NSURL*) file
{
    NSArray<NSString*>* parts = [self partsOfOutboxFile:file];
    if(parts.count < 2)
        return [NSDate distantPast];
    return [NSDate dateWithTimeIntervalSince1970:[parts[1] doubleValue]];
}

+(BOOL) isInFlight:(NSURL*) file
{
    @synchronized([MLCrashReporter class]) {
        return [crashOutboxInFlight containsObject:file.lastPathComponent];
    }
}

//keeps the newest reports (at most CRASH_OUTBOX_MAX_FILES) that are not older than CRASH_OUTBOX_MAX_AGE
+(void) trimOutbox
{
    NSDate* oldest = [NSDate dateWithTimeIntervalSinceNow:-CRASH_OUTBOX_MAX_AGE];
    NSUInteger kept = 0;
    for(NSURL* file in [self outboxFiles])        //newest first
    {
        if([self isInFlight:file])
            continue;
        BOOL tooOld = [[self dateOfOutboxFile:file] compare:oldest] == NSOrderedAscending;
        if(kept < CRASH_OUTBOX_MAX_FILES && !tooOld)
        {
            kept++;
            continue;
        }
        DDLogWarn(@"Removing crash report %@ from the outbox (limit of files or age)", file.lastPathComponent);
        [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
    }
}

//sends what is left in the outbox from an earlier launch; without a connection the files just stay there
+(void) processCrashOutbox
{
    [self trimOutbox];
    NSArray<NSURL*>* files = [self outboxFiles];
    if(files.count > 0)
        [self sendReportFiles:files allowShare:NO];
}

#pragma mark - isaCloud: sending

//polls the main queue until the condition is true or the time is over (done gets YES or NO)
+(void) waitUntil:(BOOL (^)(void)) condition timeout:(NSTimeInterval) timeout then:(void (^)(BOOL ok)) done
{
    [self pollUntil:condition deadline:[NSDate dateWithTimeIntervalSinceNow:timeout] then:done];
}

+(void) pollUntil:(BOOL (^)(void)) condition deadline:(NSDate*) deadline then:(void (^)(BOOL ok)) done
{
    if(condition())
    {
        done(YES);
        return;
    }
    if([deadline timeIntervalSinceNow] <= 0)
    {
        done(NO);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self pollUntil:condition deadline:deadline then:done];
    });
}

//an enabled account that is connected; the account of isacloud.im or autozona.cc is preferred
+(xmpp* _Nullable) connectedReportAccount
{
    NSMutableArray* list = [MLXMPPManager sharedInstance].connectedXMPP;
    NSArray<xmpp*>* accounts;
    @synchronized(list) {
        accounts = [list copy];
    }
    xmpp* first = nil;
    for(xmpp* account in accounts)
    {
        if(account.accountState < kStateBound || [[MLXMPPManager sharedInstance] getEnabledAccountForID:account.accountID] == nil)
            continue;
        NSString* domain = account.connectionProperties.identity.domain;
        if([domain hasSuffix:@"isacloud.im"] || [domain hasSuffix:@"autozona.cc"])
            return account;
        if(first == nil)
            first = account;
    }
    return first;
}

+(void) waitForReportAccount:(void (^)(xmpp* _Nullable account)) completion
{
    //no enabled account: nothing to wait for
    if([[DataLayer sharedInstance] enabledAccountList].count == 0)
    {
        completion(nil);
        return;
    }
    [self waitUntil:^BOOL{
        return [self connectedReportAccount] != nil;
    } timeout:CRASH_ACCOUNT_WAIT then:^(BOOL ok) {
        completion(ok ? [self connectedReportAccount] : nil);
    }];
}

//fetches the devicelist of reports@ (it is not a contact, so the server does not warn about its changes) and waits for its devices and bundles
+(void) prepareOMEMOOfAccount:(xmpp*) account completion:(void (^)(BOOL ok)) completion
{
    MLOMEMO* omemo = account.omemo;
    if(omemo == nil)
    {
        completion(NO);
        return;
    }
    [omemo queryOMEMODevices:CRASH_REPORTS_JID withSubscribe:NO];
    [self waitUntil:^BOOL{
        return ![omemo.state.openDevicelistFetches containsObject:CRASH_REPORTS_JID] && omemo.state.openBundleFetches[CRASH_REPORTS_JID].count == 0;
    } timeout:CRASH_OMEMO_WAIT then:^(BOOL ok) {
        if(!ok || [omemo lastDevicelistFetchErrorForJid:CRASH_REPORTS_JID] != nil)
        {
            DDLogWarn(@"Devicelist of the reports account not fetched");
            completion(NO);
            return;
        }
        //devices seen for the first time (TOFU) are accepted; with "allowMixedTrustInGroups" off, only the devices trusted explicitly
        BOOL onlyVerified = ![[HelperTools defaultsDB] boolForKey:@"allowMixedTrustInGroups"];
        NSUInteger usable = 0;
        for(NSNumber* device in [omemo knownDevicesForAddressName:CRASH_REPORTS_JID])
        {
            NSNumber* trust = [omemo getTrustLevelForJid:CRASH_REPORTS_JID andDeviceId:device];
            if(trust != nil && trust.intValue >= (onlyVerified ? MLOmemoTrusted : MLOmemoToFU))
                usable++;
        }
        DDLogInfo(@"Reports account: %lu usable OMEMO device(s)", (unsigned long)usable);
        completion(usable > 0);
    }];
}

+(void) releaseBatch:(NSArray<NSURL*>*) batch
{
    @synchronized([MLCrashReporter class]) {
        for(NSURL* file in batch)
            [crashOutboxInFlight removeObject:file.lastPathComponent];
    }
}

//sends the files to reports@; allowShare is YES when the person just said yes (then a failure opens the share sheet)
+(void) sendReportFiles:(NSArray<NSURL*>*) files allowShare:(BOOL) allowShare
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableArray<NSURL*>* batch = [NSMutableArray new];
        @synchronized([MLCrashReporter class]) {
            if(crashOutboxInFlight == nil)
                crashOutboxInFlight = [NSMutableSet new];
            for(NSURL* file in files)
                if(![crashOutboxInFlight containsObject:file.lastPathComponent] && [[NSFileManager defaultManager] fileExistsAtPath:file.path])
                {
                    [crashOutboxInFlight addObject:file.lastPathComponent];
                    [batch addObject:file];
                }
        }
        if(batch.count == 0)
            return;
        DDLogInfo(@"Sending %lu crash report(s) to the reports account...", (unsigned long)batch.count);
        [self waitForReportAccount:^(xmpp* account) {
            if(account == nil)
            {
                DDLogWarn(@"No connected account for the crash reports");
                [self finishBatch:batch unsent:batch allowShare:allowShare];
                return;
            }
            [self prepareOMEMOOfAccount:account completion:^(BOOL ok) {
                if(!ok)
                {
                    [self finishBatch:batch unsent:batch allowShare:allowShare];
                    return;
                }
                //the conversation shows up in the list of chats (a local entry only, the roster is not touched), like a chat with someone who is not a contact
                [[DataLayer sharedInstance] addActiveBuddies:CRASH_REPORTS_JID forAccount:account.accountID];
                MLContact* contact = [MLContact createContactFromJid:CRASH_REPORTS_JID andAccountID:account.accountID];
                [self sendFrom:0 ofBatch:batch account:account contact:contact allowShare:allowShare];
            }];
        }];
    });
}

//sends the files one after the other; each one has its own time limit
+(void) sendFrom:(NSUInteger) index ofBatch:(NSArray<NSURL*>*) batch account:(xmpp*) account contact:(MLContact*) contact allowShare:(BOOL) allowShare
{
    if(index >= batch.count)
    {
        [self finishBatch:batch unsent:@[] allowShare:allowShare];
        return;
    }
    NSURL* file = batch[index];
    NSArray<NSURL*>* rest = [batch subarrayWithRange:NSMakeRange(index, batch.count - index)];
    NSNumber* fileSize = [[NSFileManager defaultManager] attributesOfItemAtPath:file.path error:nil][NSFileSize];
    NSInteger uploadLimit = account.connectionProperties.uploadSize;
    if(uploadLimit > 0 && fileSize.longLongValue > uploadLimit)
    {
        DDLogWarn(@"Crash report %@ is bigger than the server limit (%ld bytes)", file.lastPathComponent, (long)uploadLimit);
        [self finishBatch:batch unsent:rest allowShare:allowShare];
        return;
    }

    __block BOOL answered = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(CRASH_SEND_WAIT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if(answered)
            return;
        answered = YES;
        DDLogWarn(@"Upload of the crash report timed out");
        [self finishBatch:batch unsent:rest allowShare:allowShare];
    });
    //the file is encrypted by the upload; the key goes in the OMEMO message. A copy with a readable name goes up
    //(ios-b<build>-<date>-<time>.mcrash.gz), because the receiving app saves the file under the name of the link
    NSURL* namedCopy = [self copyWithReadableNameOfOutboxFile:file];
    [MLFiletransfer uploadFile:namedCopy ?: file onAccount:account withEncryption:YES andCompletion:^(NSString* url, NSString* mimeType, NSNumber* size, NSError* error) {
        if(namedCopy != nil)
            [[NSFileManager defaultManager] removeItemAtURL:namedCopy error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if(answered)
                return;
            answered = YES;
            if(url == nil || error != nil)
            {
                DDLogError(@"Upload of the crash report failed: %@", error);
                [self finishBatch:batch unsent:rest allowShare:allowShare];
                return;
            }
            if(![self sendMessagesOfFile:file url:url mimeType:mimeType size:size contact:contact])
            {
                [self finishBatch:batch unsent:rest allowShare:allowShare];
                return;
            }
            //sent: out of the outbox
            [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
            [self sendFrom:index + 1 ofBatch:batch account:account contact:contact allowShare:allowShare];
        });
    }];
}

//a text line with the version, build and date of the crash, then the link to the encrypted file (OMEMO)
+(BOOL) sendMessagesOfFile:(NSURL*) file url:(NSString*) url mimeType:(NSString* _Nullable) mimeType size:(NSNumber* _Nullable) size contact:(MLContact*) contact
{
    NSArray<NSString*>* parts = [self partsOfOutboxFile:file];
    NSString* version = parts.count > 2 ? parts[2] : @"unknown";
    NSString* build = parts.count > 3 ? parts[3] : @"unknown";
    NSDateFormatter* formatter = [NSDateFormatter new];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    NSString* line = [NSString stringWithFormat:NSLocalizedString(@"Crash report of isaCloud %@ (build %@), from %@", @"text sent with a crash report: version, build and date of the crash"),
        version, build, [formatter stringFromDate:[self dateOfOutboxFile:file]]];
    MLMessage* textMessage = [[MLXMPPManager sharedInstance] sendMessageAndAddToHistory:line havingType:kMessageTypeText toContact:contact isEncrypted:YES uploadInfo:nil];
    NSDictionary* uploadInfo = @{
        @"mimeType": mimeType ?: @"application/octet-stream",
        @"size": size ?: @0,
    };
    MLMessage* fileMessage = [[MLXMPPManager sharedInstance] sendMessageAndAddToHistory:url havingType:kMessageTypeFiletransfer toContact:contact isEncrypted:YES uploadInfo:uploadInfo];
    if(textMessage == nil || fileMessage == nil)
    {
        DDLogError(@"Could not send the crash report message");
        return NO;
    }
    return YES;
}

//the files that could not be sent: the share sheet with copies of them, or they stay in the outbox
+(void) finishBatch:(NSArray<NSURL*>*) batch unsent:(NSArray<NSURL*>*) unsent allowShare:(BOOL) allowShare
{
    if(unsent.count == 0)
    {
        DDLogInfo(@"Crash reports sent to the reports account");
        [self releaseBatch:batch];
        if(allowShare)
            [self showSentAlert];
        return;
    }
    DDLogWarn(@"%lu crash report(s) not sent to the reports account", (unsigned long)unsent.count);
    if(!allowShare)
    {
        [self releaseBatch:batch];
        return;
    }
    BOOL presented = [self presentShareOfFiles:unsent onDone:^(NSArray<NSURL*>* shared) {
        //the person has the copies now (or closed the sheet): the outbox copies go
        for(NSURL* file in shared)
            [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
        [self releaseBatch:batch];
    }];
    if(!presented)
        [self releaseBatch:batch];
}

+(UIViewController* _Nullable) topViewControllerIfNoPresentation
{
    UIViewController* top = [(MonalAppDelegate*)[[UIApplication sharedApplication] delegate] getTopViewController];
    return top.presentedViewController == nil ? top : nil;
}

//the guide channel (Guia XMPP) of the account that has it, to talk about the crash
+(MLContact* _Nullable) guideRoomContact
{
    for(xmpp* account in [MLXMPPManager sharedInstance].connectedXMPP)
    {
        MLContact* contact = [MLContact createContactFromJid:CRASH_GUIDE_ROOM_JID andAccountID:account.accountID];
        if(contact != nil && contact.isMuc && contact.isListedLocally)
            return contact;
    }
    return nil;
}

+(void) openGuideRoomWithMention:(MLContact*) contact
{
    //the text box of the channel starts with "reports: " (after what the person was already writing there, if anything)
    NSString* draft = [[DataLayer sharedInstance] loadMessageDraft:contact.contactJid forAccount:contact.accountID];
    NSString* mention = [draft length] > 0 ? [NSString stringWithFormat:@"%@\nreports: ", draft] : @"reports: ";
    [[DataLayer sharedInstance] saveMessageDraft:contact.contactJid forAccount:contact.accountID withComment:mention];
    [(MonalAppDelegate*)[[UIApplication sharedApplication] delegate] openChatOfContact:contact];
}

+(void) showSentAlert
{
    UIViewController* top = [self topViewControllerIfNoPresentation];
    if(top == nil)
        return;
    UIAlertController* alertController = [UIAlertController alertControllerWithTitle:nil
                                                                             message:NSLocalizedString(@"Report sent. Thank you! If you want to share any extra information about what happened, write in the Guia XMPP channel and mention @reports.", @"crash report sent: confirmation shown after the report went out")
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    //the alert cannot hold a link, so "Guia XMPP" is a button: it opens the channel with "reports: " already in the text box
    MLContact* guide = [self guideRoomContact];
    //a "reports: " left in the channel by an earlier test is not a draft: clear it (see DataLayer saveMessageDraft)
    if(guide != nil)
    {
        NSString* leftover = [[DataLayer sharedInstance] loadMessageDraft:guide.contactJid forAccount:guide.accountID];
        if([[leftover stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] isEqualToString:@"reports:"])
            [[DataLayer sharedInstance] saveMessageDraft:guide.contactJid forAccount:guide.accountID withComment:@""];
    }
    UIAlertAction* openAction = nil;
    if(guide != nil)
        openAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Open Guia XMPP", @"Crash report: button that opens the guide channel") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction* action) {
            [self openGuideRoomWithMention:guide];
        }];
    if(openAction != nil)
        [alertController addAction:openAction];
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Crash report: confirmation button")
                                                        style:openAction != nil ? UIAlertActionStyleCancel : UIAlertActionStyleDefault
                                                      handler:nil]];
    UIColor* pink = [UIColor colorNamed:@"isaCloudPink"];
    if(pink != nil)
        alertController.view.tintColor = pink;
    if(openAction != nil)
        alertController.preferredAction = openAction;
    [top presentViewController:alertController animated:YES completion:nil];
}

//copies the files to a temporary folder (with plain names) and opens the share sheet; done gets the outbox files that were shared
+(BOOL) presentShareOfFiles:(NSArray<NSURL*>*) files onDone:(void (^)(NSArray<NSURL*>* shared)) done
{
    UIViewController* top = [self topViewControllerIfNoPresentation];
    if(top == nil)
        return NO;
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* folder = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[NSString stringWithFormat:@"crash-share-%@", [[NSUUID UUID] UUIDString]] isDirectory:YES];
    [fm createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableArray<NSURL*>* copies = [NSMutableArray new];
    NSMutableArray<NSURL*>* shared = [NSMutableArray new];
    int i = 1;
    for(NSURL* file in files)
    {
        NSURL* copy = [folder URLByAppendingPathComponent:[NSString stringWithFormat:@"CrashReport-%d.mcrash.gz", i++]];
        NSError* error = nil;
        if([fm copyItemAtURL:file toURL:copy error:&error])
        {
            [copies addObject:copy];
            [shared addObject:file];
        }
        else
            DDLogError(@"Could not copy crash report for sharing: %@", error);
    }
    if(copies.count == 0)
    {
        [fm removeItemAtURL:folder error:nil];
        return NO;
    }
    UIActivityViewController* activity = [[UIActivityViewController alloc] initWithActivityItems:copies applicationActivities:nil];
    activity.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed, NSArray* returnedItems, NSError* activityError) {
        [fm removeItemAtURL:folder error:nil];
        done(shared);
    };
    activity.popoverPresentationController.sourceView = top.view;
    activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 1, 1);
    [top presentViewController:activity animated:YES completion:nil];
    return YES;
}

@end

@implementation KSCrashReportFilterMLAlert
{
    NSString* _title;
    NSString* _message;
    NSString* _yesAnswer;
    NSString* _noAnswer;
}

-(instancetype) initWithTitle:(NSString*) title message:(NSString*) message yesAnswer:(NSString*) yesAnswer noAnswer:(NSString*) noAnswer
{
    self = [super init];
    _title = title;
    _message = message;
    _yesAnswer = yesAnswer;
    _noAnswer = noAnswer;
    return self;
}

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController* alertController = [UIAlertController alertControllerWithTitle:self->_title message:self->_message preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* yesAction = [UIAlertAction actionWithTitle:self->_yesAnswer style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction* action) {
            kscrash_callCompletion(onCompletion, reports, nil);
        }];
        UIAlertAction* noAction = [UIAlertAction actionWithTitle:self->_noAnswer style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction* action) {
            kscrash_callCompletion(onCompletion, reports, [KSNSErrorHelper errorWithDomain:[[self class] description] code:0 description:@"User declined"]);
        }];
        //"Not now" stays quiet (grey, regular weight); "Send" is the pink, bold answer
        @try {
            [noAction setValue:[UIColor secondaryLabelColor] forKey:@"titleTextColor"];
        } @catch(NSException* exception) {
            DDLogWarn(@"Could not color the 'Not now' button: %@", exception);
        }
        //the message in the main text color: the alert default (light grey) discourages reading
        @try {
            NSMutableParagraphStyle* paragraph = [NSMutableParagraphStyle new];
            paragraph.lineSpacing = 3;
            NSAttributedString* message = [[NSAttributedString alloc] initWithString:self->_message attributes:@{
                NSForegroundColorAttributeName: [UIColor labelColor],
                NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline],
                NSParagraphStyleAttributeName: paragraph,
            }];
            [alertController setValue:message forKey:@"attributedMessage"];
        } @catch(NSException* exception) {
            DDLogWarn(@"Could not color the message of the crash alert: %@", exception);
        }
        [alertController addAction:noAction];
        [alertController addAction:yesAction];
        alertController.preferredAction = yesAction;
        UIColor* pink = [UIColor colorNamed:@"isaCloudPink"];
        if(pink != nil)
            alertController.view.tintColor = pink;
        //on top of whatever is shown right now
        UIViewController* top = [(MonalAppDelegate*)[[UIApplication sharedApplication] delegate] getTopViewController];
        while(top.presentedViewController != nil)
            top = top.presentedViewController;
        [top presentViewController:alertController animated:YES completion:nil];
    });
}

@end

@implementation KSCrashReportFilterMLEmpty

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    DDLogVerbose(@"KSCrashReportFilterMLEmpty started...");
    NSMutableArray* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(NSUInteger i = 0; i < reports.count; i++)
        [filteredReports addObject:[KSCrashReportString reportWithValue:@""]];
    DDLogVerbose(@"KSCrashReportFilterMLEmpty finished...");
    kscrash_callCompletion(onCompletion, filteredReports, nil);
}

@end

@implementation KSCrashReportFilterMLCaptureMetadata

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    DDLogVerbose(@"KSCrashReportFilterMLCaptureMetadata started...");
    //the date format of the KSCrash report (see KSCrashReportFilterAppleFmt)
    NSDateFormatter* formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'SSSSSS'Z'";
    NSMutableArray<NSDictionary*>* metadata = [NSMutableArray arrayWithCapacity:[reports count]];
    for(id<KSCrashReport> report_ in reports)
    {
        NSMutableDictionary* meta = [NSMutableDictionary new];
        NSDictionary* report = [report_ untypedValue];
        if([report isKindOfClass:[NSDictionary class]])
        {
            NSDictionary* info = report[@"report"];
            NSString* timestamp = [info isKindOfClass:[NSDictionary class]] ? info[@"timestamp"] : nil;
            NSDate* date = [timestamp isKindOfClass:[NSString class]] ? [formatter dateFromString:timestamp] : nil;
            if(date != nil)
                meta[@"date"] = date;
            NSDictionary* system = report[@"system"];
            if([system isKindOfClass:[NSDictionary class]])
            {
                if([system[@"CFBundleShortVersionString"] isKindOfClass:[NSString class]])
                    meta[@"version"] = system[@"CFBundleShortVersionString"];
                if([system[@"CFBundleVersion"] isKindOfClass:[NSString class]])
                    meta[@"build"] = system[@"CFBundleVersion"];
            }
        }
        [metadata addObject:meta];
    }
    @synchronized([MLCrashReporter class]) {
        crashReportMetadata = metadata;
    }
    DDLogVerbose(@"KSCrashReportFilterMLCaptureMetadata finished...");
    kscrash_callCompletion(onCompletion, reports, nil);
}

@end

@implementation KSCrashReportFilterMLAddAuxInfo

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    DDLogVerbose(@"KSCrashReportFilterMLAddAuxInfo started...");
    NSMutableArray<id<KSCrashReport>>* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(id<KSCrashReport> report_ in reports)
    {
        NSDictionary* report = [report_ untypedValue];
        NSMutableString* auxData = [NSMutableString new];

        //add version of monal reporting this crash
        [auxData appendString:[NSString stringWithFormat:@"reporterVersion: %@\n", [HelperTools appBuildVersionInfoFor:MLVersionTypeLog]]];

        //add user data to aux data
        for(NSString* userKey in report[@"user"])
            [auxData appendString:[NSString stringWithFormat:@"%@: %@\n", userKey, report[@"user"][userKey]]];

        //add crash_info_message and crash_info_message2 to aux data
        NSMutableString* crashInfos = [NSMutableString new];
        for(NSDictionary* binaryImage in report[@"binary_images"])
        {
            if(binaryImage[@"crash_info_message"] != nil)
                [crashInfos appendString:[NSString stringWithFormat:@"message at %@:\n%@\n\n", binaryImage[@"name"], binaryImage[@"crash_info_message"]]];
            if(binaryImage[@"crash_info_message2"] != nil)
                [crashInfos appendString:[NSString stringWithFormat:@"message2 at %@:\n%@\n\n", binaryImage[@"name"], binaryImage[@"crash_info_message2"]]];
            if(binaryImage[@"crash_info_signature"] != nil)
                [crashInfos appendString:[NSString stringWithFormat:@"signature at %@:\n%@\n\n", binaryImage[@"name"], binaryImage[@"crash_info_signature"]]];
            if(binaryImage[@"crash_info_backtrace"] != nil)
                [crashInfos appendString:[NSString stringWithFormat:@"backtrace at %@:\n%@\n\n", binaryImage[@"name"], binaryImage[@"crash_info_backtrace"]]];
        }
        if([crashInfos length] > 0)
            [auxData appendString:[NSString stringWithFormat:@"\nAvailable crash info messages:\n\n%@", crashInfos]];

        [filteredReports addObject:[KSCrashReportString reportWithValue:auxData]];
    }
    DDLogVerbose(@"KSCrashReportFilterMLAddAuxInfo finished...");
    kscrash_callCompletion(onCompletion, filteredReports, nil);
}

@end

@implementation KSCrashReportFilterMLAddMLLogfile

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    DDLogVerbose(@"KSCrashReportFilterMLAddMLLogfile started...");
    NSMutableArray<id<KSCrashReport>>* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(id<KSCrashReport> report_ in reports)
    {
        NSDictionary* report = [report_ untypedValue];
        NSString* logfileCopy = report[@"user"][@"logfileCopy"];
        NSData* logfileData = [NSData new];
        if(logfileCopy != nil)
        {
            DDLogDebug(@"Adding logfile copy of '%@' from '%@' to crash report...", report[@"user"][@"currentLogfile"], report[@"user"][@"logfileCopy"]);
            logfileData = [NSData dataWithContentsOfFile:logfileCopy];
            DDLogVerbose(@"NSData of logfile copy: %@", logfileData);
            NSError* error = nil;
            [[NSFileManager defaultManager] removeItemAtPath:logfileCopy error:&error];
            if(error != nil)
                DDLogError(@"Failed to delete logfileCopy: %@", error);
            if(logfileData == nil)
                logfileData = [NSData new];
        }
        DDLogVerbose(@"Converting logfile data to hex...");
        [filteredReports addObject:[KSCrashReportString reportWithValue:[HelperTools hexadecimalString:logfileData]]];
    }
    DDLogVerbose(@"KSCrashReportFilterMLAddMLLogfile finished...");
    kscrash_callCompletion(onCompletion, filteredReports, nil);
}

@end

@implementation KSCrashReportFilterMLAddProfraw

-(void) filterReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    DDLogVerbose(@"KSCrashReportFilterMLAddProfraw started...");
    NSMutableArray<id<KSCrashReport>>* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(id<KSCrashReport> report_ in reports)
    {
        NSDictionary* report = [report_ untypedValue];
        NSString* profileCopy = report[@"user"][@"profileCopy"];
        NSData* profileData = [NSData new];
        if(profileCopy != nil)
        {
            DDLogDebug(@"Adding profile copy of '%@' from '%@' to crash report...", report[@"user"][@"currentProfile"], report[@"user"][@"profileCopy"]);
            profileData = [NSData dataWithContentsOfFile:profileCopy];
            DDLogVerbose(@"NSData of profile copy: %@", profileData);
            NSError* error = nil;
            [[NSFileManager defaultManager] removeItemAtPath:profileCopy error:&error];
            if(error != nil)
                DDLogError(@"Failed to delete profileCopy: %@", error);
            if(profileData == nil)
                profileData = [NSData new];
        }
        DDLogVerbose(@"Converting profile data to hex...");
        [filteredReports addObject:[KSCrashReportString reportWithValue:[HelperTools hexadecimalString:profileData]]];
    }
    DDLogVerbose(@"KSCrashReportFilterAddProfile finished...");
    kscrash_callCompletion(onCompletion, filteredReports, nil);
}

@end
