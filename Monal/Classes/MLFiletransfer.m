//
//  MLFiletransfer.m
//  monalxmpp
//
//  Created by Thilo Molitor on 12.11.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/MLFileTransfer.h>
#import <monalxmpp/MLFiletransferInfo.h>
#import <monalxmpp/DataLayer.h>
#import "MLEncryptedPayload.h"
#import <monalxmpp/xmpp.h>
#import "AESGcm.h"
#import <monalxmpp/MLXMPPManager.h>
#import <monalxmpp/MLNotificationQueue.h>

@import MobileCoreServices;
@import UniformTypeIdentifiers;
@import UIKit.UIImage;
@import AVFoundation;

//monal version 7.x, state counter: 001
#define CURRENT_FILETRANSFER_DATA_VERSION @7001

//isaCloud: photo reduction before the upload (docs/analise-comprimir-imagens.md): "large" reduces photos above 2 MiB, "always" every photo
#define ISACLOUD_IMAGE_COMPRESSION_LARGE_BYTES (2 * 1024 * 1024)
#define ISACLOUD_IMAGE_MAX_PIXEL_SIZE 1920
//isaCloud: video conversion before the upload (docs/analise-comprimir-videos.md): up to 512 KiB is sent as it is, longer than 300 s is not sent
#define ISACLOUD_VIDEO_KEEP_BYTES (512 * 1024)
#define ISACLOUD_VIDEO_MAX_SECONDS 300
#define ISACLOUD_VIDEO_CONVERSION_TIMEOUT (10 * 60)
static CGImageRef createWhiteBackedCopyOfImage(CGImageRef image) CF_RETURNS_RETAINED;
//isaCloud: describes pixel size and EXIF orientation of an image, only for the photo log lines
static NSString* describeImageSource(CGImageSourceRef source);
static NSString* describeImageDataForLog(NSData* data);
static NSString* describeImageFileForLog(NSURL* fileUrl);
static BOOL imageFileHasOrientationTag(NSURL* fileUrl);

static NSFileManager* _fileManager;
static NSString* _documentCacheDir;
static NSObject* _hardlinkingSyncObject;
static NSObject* _stateSyncObject;
static NSMutableDictionary<NSString*, NSNumber*>* _expectedDownloadSizes;
static NSMutableSet* _currentlyTransfering;
//isaCloud: the state is persisted on this serial queue, never while holding _stateSyncObject (see storeState)
static dispatch_queue_t _storeStateQueue;
static NSDictionary* _pendingStoreState;            //newest state snapshot waiting to be persisted, protected by _stateSyncObject
static BOOL _storeStateScheduled;                   //a persist block is queued and will pick up _pendingStoreState, protected by _stateSyncObject

@implementation MLFiletransfer

+(void) initialize
{
    NSError* error;
    _hardlinkingSyncObject = [NSObject new];
    _stateSyncObject = [NSObject new];
    _fileManager = [NSFileManager defaultManager];
    _documentCacheDir = [[HelperTools getContainerURLForPathComponents:@[@"documentCache"]] path];
    
    [_fileManager createDirectoryAtURL:[NSURL fileURLWithPath:_documentCacheDir] withIntermediateDirectories:YES attributes:nil error:&error];
    if(error)
        @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
    [HelperTools configureFileProtectionFor:_documentCacheDir];
    
    _currentlyTransfering = [NSMutableSet new];
    _expectedDownloadSizes = [NSMutableDictionary new];
    _storeStateQueue = dispatch_queue_create("im.monal.filetransfer.storeState", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
}

+(void) loadState
{
    NSDictionary* state = [[DataLayer sharedInstance] getFiletransferState];
    //DDLogVerbose(@"Setting MLFileTransfer state to: %@", state);
    
    //ignore state having wrong version code
    if(!state[@"version"] || ![state[@"version"] isEqual:CURRENT_FILETRANSFER_DATA_VERSION])
    {
        DDLogDebug(@"Ignoring MLFiletransfer state having wrong version: %@ != %@", state[@"version"], CURRENT_FILETRANSFER_DATA_VERSION);
        return;
    }
    
    @synchronized(_stateSyncObject) {
        _currentlyTransfering = state[@"currentlyTransfering"];
        _expectedDownloadSizes = state[@"expectedDownloadSizes"];
    }
}

//isaCloud: callers may hold the database write transaction (e.g. the xmpp receive queue while processing a message),
//so this must never write to the database while holding _stateSyncObject, and never block on the persist queue:
//we only take a snapshot here and persist it asynchronously, coalescing writes (the newest snapshot is always written)
+(void) storeState
{
    @synchronized(_stateSyncObject) {
        _pendingStoreState = @{
            @"version": CURRENT_FILETRANSFER_DATA_VERSION,
            @"currentlyTransfering": [_currentlyTransfering copy],
            @"expectedDownloadSizes": [_expectedDownloadSizes copy],
        };
        //a queued persist block that has not read its snapshot yet will write this one
        if(_storeStateScheduled)
            return;
        _storeStateScheduled = YES;
    }
    dispatch_async(_storeStateQueue, ^{
        NSDictionary* state;
        @synchronized(_stateSyncObject) {
            state = _pendingStoreState;
            _pendingStoreState = nil;
            _storeStateScheduled = NO;
        }
        //DDLogVerbose(@"Storing MLFileTransfer state: %@", state);
        [[DataLayer sharedInstance] setFiletransferState:state];
    });
}

+(BOOL) isIdle
{
    @synchronized(_stateSyncObject) {
        return [_currentlyTransfering count] == 0;
    }
}

+(void) addTransfer:(id) obj
{
    @synchronized(_stateSyncObject) {
        [_currentlyTransfering addObject:obj];
        [self storeState];
    }
}

+(void) markAsComplete:(id) obj
{
    @synchronized(_stateSyncObject) {
        [_currentlyTransfering removeObject:obj];
        [self storeState];
    }
    if(self.isIdle)
        //don't queue this notification because it should be handled immediately
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalFiletransfersIdle object:self];
}

+(BOOL) isFileForHistoryIdInTransfer:(NSNumber*) historyId
{
    @synchronized(_stateSyncObject) {
        if([_currentlyTransfering containsObject:historyId])
            return YES;
        return NO;
    }
}

+(BOOL) isFileAtPathInTransfer:(NSString*) path
{
    @synchronized(_stateSyncObject) {
        if([_currentlyTransfering containsObject:path])
            return YES;
        return NO;
    }
}

+(void) checkMimeTypeAndSizeForHistoryID:(NSNumber*) historyId
{
    NSString* url;
    MLMessage* msg = [MLMessage createMessageFromHistoryID:historyId];
    if(!msg)
    {
        DDLogError(@"historyId %@ does not yield an MLMessage object, aborting", historyId);
        return;
    }
    if(msg.retracted || msg.deletedLocally)
    {
        DDLogWarn(@"Canceling mimeType check because the message was retracted or deleted locally. historyId = %@", historyId);
        return;
    }
    url = [self genCanonicalUrl:msg.messageText];
    //isaCloud: read the database value before taking _stateSyncObject (fileInfo reads the database)
    NSNumber* expectedSize = msg.fileInfo.size;
    @synchronized(_stateSyncObject) {
        if(_expectedDownloadSizes[url] == nil)
        {
            _expectedDownloadSizes[url] = expectedSize;
            [self storeState];
        }
    }
    //make sure we don't check or download this twice
    @synchronized(_stateSyncObject) {
        if([self isFileForHistoryIdInTransfer:historyId])
        {
            DDLogDebug(@"Already checking/downloading this content, ignoring");
            return;
        }
        [self addTransfer:historyId];
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        DDLogInfo(@"Requesting mime-type and size for historyID %@ from http server", historyId);
        NSMutableURLRequest* request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
        if([[HelperTools defaultsDB] boolForKey: @"useDnssecForAllConnections"])
            request.requiresDNSSECValidation = YES;
        request.HTTPMethod = @"HEAD";
        request.cachePolicy = NSURLRequestReturnCacheDataElseLoad;

        NSURLSession* session = [HelperTools createEphemeralURLSession];
        [[session dataTaskWithRequest:request completionHandler:^(NSData* _Nullable data __unused, NSURLResponse* _Nullable response, NSError* _Nullable error) {
            if(msg.retracted || msg.deletedLocally)
            {
                DDLogDebug(@"Ignoring mimeType/size check results because the corresponding message was retracted or deleted while fetching the headers. historyId = %@", historyId);
                [self markAsComplete:historyId];
                return;
            }
            if(error != nil)
            {
                DDLogError(@"Failed to fetch headers of %@ at %@: %@", msg, url, error);
                //check done, remove from "currently checking/downloading list" and set error
                [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:[NSString stringWithFormat:NSLocalizedString(@"Failed to fetch download metadata: %@", @""), error] forMessage:msg];
                [self markAsComplete:historyId];
                return;
            }
            NSDictionary* headers = ((NSHTTPURLResponse*)response).allHeaderFields;
            NSString* mimeType = [[headers objectForKey:@"Content-Type"] lowercaseString];
            if(mimeType)                                                                                                                                                                 
                mimeType = [[mimeType componentsSeparatedByString:@";"] firstObject];
            NSNumber* contentLength = [headers objectForKey:@"Content-Length"] ? [NSNumber numberWithLongLong:([[headers objectForKey:@"Content-Length"] longLongValue])] : @(-1);
            if(!mimeType)       //default mime type if none was returned by http server
                mimeType = @"application/octet-stream";
            
            //try to deduce the content type from a given file extension if needed and possible
            if([mimeType isEqualToString:@"application/octet-stream"])
            {
                NSURLComponents* urlComponents = [NSURLComponents componentsWithString:url];
                if(urlComponents)
                    mimeType = [self getMimeTypeOfOriginalFile:urlComponents.path];
            }
            
            //make sure we *always* have a mime type
            if(!mimeType)
                mimeType = @"application/octet-stream";
            
            DDLogInfo(@"Got http mime-type and size for historyID %@: %@ (%@)", historyId, mimeType, contentLength);
            DDLogDebug(@"Updating db and sending out kMonalMessageFiletransferUpdateNotice");
            
            //update db with content type and size
            [[DataLayer sharedInstance] setFiletransferInfoForHistoryId:historyId withMimeType:mimeType andSize:contentLength];

            //send out update notification
            xmpp* account = [[MLXMPPManager sharedInstance] getEnabledAccountForID:msg.accountID];
            if(account != nil)      //don't send out update notices for already deleted accounts
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalMessageFiletransferUpdateNotice object:account userInfo:@{ @"message": msg }];
            else
                return;             //abort here without autodownloading if account was already deleted
            
            //try to autodownload if sizes match
            long autodownloadMaxSize = [[HelperTools defaultsDB] integerForKey:@"AutodownloadFiletransfersWifiMaxSize"];
            if([[MLXMPPManager sharedInstance] onMobile])
               autodownloadMaxSize = [[HelperTools defaultsDB] integerForKey:@"AutodownloadFiletransfersMobileMaxSize"];
            if(
                [[HelperTools defaultsDB] boolForKey:@"AutodownloadFiletransfers"] &&
                [contentLength intValue] >= 0 &&        //-1 means we don't know the size --> don't autodownload files of unknown sizes
                [contentLength integerValue] <= autodownloadMaxSize
            )
            {
                DDLogInfo(@"Autodownloading file");
                [self downloadFileForHistoryID:historyId andForceDownload:YES];     //ignore already existing _currentlyTransfering entry leftover from this header check
            }
            else
            {
                //check done, remove from "currently checking/downloading list"
                [self markAsComplete:historyId];
            }
                
        }] resume];
    });
}



//### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
//************************************************* OLD NON_PROMISE API *************************************************
//### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###



+(void) downloadFileForHistoryID:(NSNumber*) historyId
{
    [self downloadFileForHistoryID:historyId andForceDownload:NO];
}

+(void) downloadFileForHistoryID:(NSNumber*) historyId andForceDownload:(BOOL) forceDownload
{
    MLMessage* msg = [MLMessage createMessageFromHistoryID:historyId];
    if(!msg)
    {
        DDLogError(@"historyId %@ does not yield an MLMessage object, aborting", historyId);
        return;
    }
    //make sure we don't check or download this twice (but only do this if the download is not forced anyway)
    @synchronized(_stateSyncObject)
    {
        if(!forceDownload && [self isFileForHistoryIdInTransfer:historyId])
        {
            DDLogDebug(@"Already checking/downloading this content, ignoring");
            return;
        }
        [self addTransfer:historyId];
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        DDLogInfo(@"Downloading file for historyID %@", historyId);
        NSString* url = [self genCanonicalUrl:msg.messageText];
        NSURLComponents* urlComponents = [NSURLComponents componentsWithString:msg.messageText];
        if(!urlComponents)
        {
            DDLogError(@"url components decoding failed for %@", msg);
            [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:NSLocalizedString(@"Failed to decode download link", @"") forMessage:msg];
            [self markAsComplete:historyId];
            return;
        }
        
        NSURLSession* session = [HelperTools createBackgroundURLSession];
        NSURLSessionDownloadTask* task = [session downloadTaskWithURL:[NSURL URLWithString:url]];
        task.taskDescription = [HelperTools hexadecimalString:[HelperTools serializeObject:@{
            @"handler": $newHandler(self, handleFileDownload,
                $ID(url),
                $ID(historyId),
            ),
            @"url": url,
            @"historyId": historyId,
        }]];
        [task resume];
    });
}

$$class_handler(handleFileDownload, $$ID(NSString*, url), $$ID(NSNumber*, historyId), $_ID(NSURL*, location), $_ID(NSHTTPURLResponse*, response), $_ID(NSError*, error))
    [_expectedDownloadSizes removeObjectForKey:url];
    
    MLMessage* msg = [MLMessage createMessageFromHistoryID:historyId];
    if(msg == nil || msg.retracted || msg.deletedLocally)
    {
        DDLogDebug(@"Discarding downloaded file because its message was retracted or deleted during the download. historyId = %@", historyId);
        // No need to remove the attachment thumbnail because it hasn't been generated.
        [_fileManager removeItemAtPath:location.path error:nil];
        [self markAsComplete:historyId];
        return;
    }
    if(error || response == nil)
    {
        DDLogError(@"File download for %@ failed: %@", msg, error);
        [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:[NSString stringWithFormat:NSLocalizedString(@"Failed to download file: %@", @""), error] forMessage:msg];
        [self markAsComplete:historyId];
        return;
    }
    if(response.statusCode < 200 || response.statusCode > 299)      //check for proper status code
    {
        NSString* errorText = [NSString stringWithFormat:@"%@ %@", @(response.statusCode), [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode]];
        DDLogError(@"File download for %@ failed: %@", msg, errorText);
        [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:[NSString stringWithFormat:NSLocalizedString(@"Failed to download file: %@", @""), errorText] forMessage:msg];
        [self markAsComplete:historyId];
        return;
    }
    
    NSURLComponents* urlComponents = [NSURLComponents componentsWithString:msg.messageText];
    NSDictionary* headers = response.allHeaderFields;
    NSString* mimeType = [[headers objectForKey:@"Content-Type"] lowercaseString];
    if(mimeType)                                                                                                                                                                 
        mimeType = [[mimeType componentsSeparatedByString:@";"] firstObject];
    if(!mimeType)
        mimeType = @"application/octet-stream";
    
    //try to deduce the content type from a given file extension if needed and possible
    if([mimeType isEqualToString:@"application/octet-stream"])
        mimeType = [self getMimeTypeOfOriginalFile:urlComponents.path];
    
    //make sure we *always* have a mime type
    if(!mimeType)
        mimeType = @"application/octet-stream";
    
    NSString* cacheFilePath = [self calculateCacheFilePathForNewUrl:msg.messageText andMimeType:mimeType];
    
    //encrypted filetransfer
    if([[urlComponents.scheme lowercaseString] isEqualToString:@"aesgcm"])
    {
        DDLogInfo(@"Decrypting encrypted filetransfer stored at '%@'...", location);
        if(urlComponents.fragment.length < 88)
        {
            DDLogError(@"File download for %@ failed: %@", msg, error);
            [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:NSLocalizedString(@"Failed to decode encrypted link", @"") forMessage:msg];
            [self markAsComplete:historyId];
            return;
        }
        int ivLength = 24;
        //format is iv+32byte key
        NSData* key = [HelperTools dataWithHexString:[urlComponents.fragment substringWithRange:NSMakeRange(ivLength, 64)]];
        NSData* iv = [HelperTools dataWithHexString:[urlComponents.fragment substringToIndex:ivLength]];
        
        //decrypt data with given key and iv
        NSData* encryptedData = [NSData dataWithContentsOfURL:location];
        if(encryptedData && encryptedData.length > 0 && key && key.length == 32 && iv && iv.length == 12)
        {
            NSData* decryptedData = [AESGcm decrypt:encryptedData withKey:key andIv:iv withAuth:nil];
            if(decryptedData == nil)
            {
                DDLogError(@"File download decryption failed for %@", msg);
                [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:NSLocalizedString(@"Failed to decrypt download", @"") forMessage:msg];
                [self markAsComplete:historyId];
                return;
            }
            [decryptedData writeToFile:cacheFilePath options:NSDataWritingAtomic error:&error];
            if(error)
            {
                DDLogError(@"File download for %@ failed: %@", msg, error);
                [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:NSLocalizedString(@"Failed to write decrypted download into cache directory", @"") forMessage:msg];
                [self markAsComplete:historyId];
                return;
            }
            MLAssert([_fileManager fileExistsAtPath:cacheFilePath], @"cache file should be there!", (@{@"cacheFilePath": cacheFilePath}));
            [HelperTools configureFileProtectionFor:cacheFilePath];
        }
        else
        {
            DDLogError(@"Failed to decrypt file (iv, key, data length checks failed) for %@", msg);
            [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:NSLocalizedString(@"Failed to decrypt filetransfer", @"") forMessage:msg];
            [self markAsComplete:historyId];
            return;
        }
    }
    else        //cleartext filetransfer
    {
        //hardlink file to our cache directory
        //it will be removed once this completion returns, even if moved to a new location (this seems to be a ios16 bug)
        DDLogInfo(@"Hardlinking downloaded file from '%@' to document cache at '%@'...", [location path], cacheFilePath);
        error = [HelperTools hardLinkOrCopyFile:[location path] to:cacheFilePath];
        //isaCloud: the cache file is named by the url, so a file already there is this same file, downloaded by another account of this
        //device that is in the same room (both get the message). That is not an error: the copy failed only because the file exists
        if(error && [_fileManager fileExistsAtPath:cacheFilePath])
        {
            DDLogWarn(@"Downloaded file for %@ is already in the document cache (another account of this device got it too), using it: %@", msg, error);
            error = nil;
        }
        if(error)
        {
            DDLogError(@"File download for %@ failed: %@", msg, error);
            [self setErrorType:NSLocalizedString(@"Download error", @"") andErrorText:[NSString stringWithFormat:NSLocalizedString(@"Failed to copy downloaded file into cache directory: %@", @""), error] forMessage:msg];
            [self markAsComplete:historyId];
            return;
        }
        MLAssert([_fileManager fileExistsAtPath:cacheFilePath], @"cache file should be there!", (@{@"cacheFilePath": cacheFilePath}));
        [HelperTools configureFileProtectionFor:cacheFilePath];
    }
    
    //hardlink cache file if possible
    [self hardlinkFileForMessage:msg];
    
    NSNumber* filetransferSize = @([[_fileManager attributesOfItemAtPath:cacheFilePath error:nil] fileSize]);
    DDLogDebug(@"Updating db and sending out kMonalMessageFiletransferUpdateNotice");
    //update db with content type and size
    [[DataLayer sharedInstance] setFiletransferInfoForHistoryId:historyId withMimeType:mimeType andSize:filetransferSize];

    //send out update notification
    xmpp* account = [[MLXMPPManager sharedInstance] getEnabledAccountForID:msg.accountID];
    if(account != nil)      //don't send out update notices for already deleted accounts
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalMessageFiletransferUpdateNotice object:account userInfo:@{ @"message": msg }];
    else
        [_fileManager removeItemAtPath:cacheFilePath error:nil];
    
    //download done, remove from "currently checking/downloading list"
    [self markAsComplete:historyId];
$$

$$class_handler(handleHardlinking, $$ID(xmpp*, account), $$ID(NSString*, cacheFilePath), $$ID((NSArray<NSString*>*), hardlinkPathComponents), $$BOOL(direct))
    NSError* error;    
    
    if([HelperTools isAppExtension])
    {
        DDLogWarn(@"NOT hardlinking cache file at '%@' into documents directory at '%@': we STILL are in the appex, rescheduling this to next account connect", cacheFilePath, [hardlinkPathComponents componentsJoinedByString:@"/"]);
        //the reconnect handler framework will add $ID(account) to the callerArgs, no need to add an accountID etc. here
        //direct=YES is indicating that this hardlinking handler was called directly instead of serializing/unserializing it to/from db
        //AND that we are in the mainapp currently
        //always use direct = NO here, to make sure the file is hardlinkable even if the direct handling depicted above changes and
        //calls from the mainapp are serialized to db, too
        [account addReconnectionHandler:$newHandler(self, handleHardlinking,
            $ID(cacheFilePath),
            $ID(hardlinkPathComponents),
            $BOOL(direct, NO)
        )];
        return;
    }
    
    if(![_fileManager fileExistsAtPath:cacheFilePath])
    {
        DDLogWarn(@"Could not hardlink cache file, file not present: %@", cacheFilePath);
        return;
    }
    
    @synchronized(_hardlinkingSyncObject) {
        //copy file created in appex to a temporary location and then rename it to be at the original location
        //this allows hardlinking later on because now the mainapp owns that file while it had only read/write access before
        if(!direct)
        {
            NSString* cacheFilePathTMP = [cacheFilePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:[NSString stringWithFormat:@"tmp.%@", cacheFilePath.lastPathComponent]];
            DDLogInfo(@"Copying appex-created cache file '%@' to '%@' before deleting old file and renaming our copy...", cacheFilePath, cacheFilePathTMP);
            [_fileManager removeItemAtPath:cacheFilePathTMP error:nil];     //remove tmp file if already present
            [_fileManager copyItemAtPath:cacheFilePath toPath:cacheFilePathTMP error:&error];
            if(error)
            {
                DDLogError(@"Could not copy cache file to tmp file: %@", error);
#ifdef DEBUG
                @throw [NSException exceptionWithName:@"ERROR_WHILE_COPYING_CACHEFILE" reason:@"Could not copy cacheFile!" userInfo:@{
                    @"cacheFilePath": cacheFilePath,
                    @"cacheFilePathTMP": cacheFilePathTMP
                }];
#endif
                return;
            }
            
            [_fileManager removeItemAtPath:cacheFilePath error:&error];
            if(error)
            {
                DDLogError(@"Could not delete original cache file: %@", error);
#ifdef DEBUG
                @throw [NSException exceptionWithName:@"ERROR_WHILE_DELETING_CACHEFILE" reason:@"Could not delete cacheFile!" userInfo:@{
                    @"cacheFilePath": cacheFilePath
                }];
#endif
                return;
            }
            
            [_fileManager moveItemAtPath:cacheFilePathTMP toPath:cacheFilePath error:&error];
            if(error)
            {
                DDLogError(@"Could not rename tmp file to cache file: %@", error);
#ifdef DEBUG
                @throw [NSException exceptionWithName:@"ERROR_WHILE_RENAMING_CACHEFILE" reason:@"Could not rename cacheFileTMP to cacheFile!" userInfo:@{
                    @"cacheFilePath": cacheFilePath,
                    @"cacheFilePathTMP": cacheFilePathTMP
                }];
#endif
                return;
            }
        }
        
        if([[HelperTools defaultsDB] boolForKey:@"hardlinkFiletransfersIntoDocuments"])
        {
            NSURL* hardLink = [[_fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
            for(NSString* pathComponent in hardlinkPathComponents)
                hardLink = [hardLink URLByAppendingPathComponent:pathComponent];
            
            DDLogInfo(@"Hardlinking cache file at '%@' into documents directory at '%@'...", cacheFilePath, hardLink);
            if(![_fileManager fileExistsAtPath:[hardLink.URLByDeletingLastPathComponent path]])
            {
                DDLogVerbose(@"Creating hardlinking dir struct at '%@'...", hardLink.URLByDeletingLastPathComponent); 
                [_fileManager createDirectoryAtURL:hardLink.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication} error:&error];
                if(error)
                    DDLogWarn(@"Ignoring error creating hardlinking dir struct at '%@': %@", hardLink, error);
                else
                    [HelperTools configureFileProtection:NSFileProtectionCompleteUntilFirstUserAuthentication forFile:[hardLink path]];
            }
            
            //don't throw any error if the file aready exists, because it could be a rare collision (we only use 16 bit random numbers to keep the file prefix short)
            if([_fileManager fileExistsAtPath:[hardLink path]])
                DDLogWarn(@"Not hardlinking file '%@' to '%@': file already exists (maybe a rare collision?)...", cacheFilePath, hardLink);
            else
            {
                DDLogVerbose(@"Hardlinking cache file '%@' to '%@'...", cacheFilePath, hardLink);
                error = [HelperTools hardLinkOrCopyFile:cacheFilePath to:[hardLink path]];
                if(error)
                {
                    DDLogError(@"Error creating hardlink: %@", error);
                    @throw [NSException exceptionWithName:@"ERROR_WHILE_HARDLINKING_FILE" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
                }
            }
        }
    }
$$

+(void) hardlinkFileForMessage:(MLMessage*) msg
{
    MLFiletransferInfo* fileInfo = msg.fileInfo;
    xmpp* account = [[MLXMPPManager sharedInstance] getEnabledAccountForID:msg.accountID];
    if(account == nil)
        return;
    
    NSString* groupDisplayName = nil;
    NSString* fromDisplayName = nil;
    MLContact* contact = [MLContact createContactFromJid:msg.buddyName andAccountID:msg.accountID];
    if(msg.isMuc)
    {
        groupDisplayName = contact.contactDisplayName;
        fromDisplayName = msg.contactDisplayName;
    }
    else
        fromDisplayName = contact.contactDisplayName;
    
    //this resembles to /Files/<account_jid>/<contact_name> for 1:1 contacts and /Files/<account_jid>/<group_name>/<contact_in_group_name> for mucs (channels AND groups)
    NSMutableArray* hardlinkPathComponents = [NSMutableArray new];
    [hardlinkPathComponents addObject:account.connectionProperties.identity.jid];
    if(groupDisplayName != nil)
        [hardlinkPathComponents addObject:groupDisplayName];
    else
        [hardlinkPathComponents addObject:fromDisplayName];
    
    //put incoming and outgoing files in different directories
    if(msg.inbound)
    {
        //put every mime-type in its own type directory
        if(fileInfo.isImage)
            [hardlinkPathComponents addObject:NSLocalizedString(@"Received Images", @"directory for downloaded images")];
        else if(fileInfo.isVideo)
            [hardlinkPathComponents addObject:NSLocalizedString(@"Received Videos", @"directory for downloaded videos")];
        else if(fileInfo.isAudio)
            [hardlinkPathComponents addObject:NSLocalizedString(@"Received Audios", @"directory for downloaded audios")];
        else
            [hardlinkPathComponents addObject:NSLocalizedString(@"Received Files", @"directory for downloaded files")];
        
        //add fromDisplayName inside the "received xxx" dir so that the received and sent dirs are at the same level
        if(groupDisplayName != nil)
            [hardlinkPathComponents addObject:fromDisplayName];
    }
    else
    {
        //put every mime-type in its own type directory
        if(fileInfo.isImage)
            [hardlinkPathComponents addObject:NSLocalizedString(@"Sent Images", @"directory for downloaded images")];
        else if(fileInfo.isVideo)
            [hardlinkPathComponents addObject:NSLocalizedString(@"Sent Videos", @"directory for downloaded videos")];
        else if(fileInfo.isAudio)
            [hardlinkPathComponents addObject:NSLocalizedString(@"Sent Audios", @"directory for downloaded audios")];
        else
            [hardlinkPathComponents addObject:NSLocalizedString(@"Sent Files", @"directory for downloaded files")];
    }
    
    u_int16_t i=(u_int16_t)arc4random();
    NSString* randomID = [HelperTools hexadecimalString:[NSData dataWithBytes: &i length: sizeof(i)]];
    NSString* fileExtension = fileInfo.fileExtension;
    fileExtension = [fileExtension substringToIndex:min(8, fileExtension.length)];
    NSString* fileBasename = [fileInfo.filename stringByDeletingPathExtension];
    fileBasename = [fileBasename substringToIndex:min(64, fileBasename.length)];
    [hardlinkPathComponents addObject:[[NSString stringWithFormat:@"%@_%@", fileBasename, randomID] stringByAppendingPathExtension:fileExtension]];
    
    MLAssert(fileInfo.cacheFilePath != nil, @"cacheFilePath should never be empty here!", (@{@"fileInfo": fileInfo}));
    
    MLHandler* handler = $newHandler(self, handleHardlinking, $ID(cacheFilePath, fileInfo.cacheFilePath), $ID(hardlinkPathComponents), $BOOL(direct, NO));
    if([HelperTools isAppExtension])
    {
        DDLogWarn(@"NOT hardlinking cache file at '%@' into documents directory at %@: we are in the appex, rescheduling this to next account connect", fileInfo.cacheFilePath, [hardlinkPathComponents componentsJoinedByString:@"/"]);
        [account addReconnectionHandler:handler];       //the reconnect handler framework will add $ID(account) to the callerArgs, no need to add an accountID etc. here
    }
    else
        $call(handler, $ID(account), $BOOL(direct, YES));       //no reconnect handler framework used, explicitly bind $ID(account) via callerArgs
}

+(void) deleteFileForMessage:(MLMessage*) msg
{
    if(![msg.messageType isEqualToString:kMessageTypeFiletransfer])
        return;
    MLFiletransferInfo* info = msg.fileInfo;
    if(info.downloadState < DownloadStateComplete)
        return;
    DDLogInfo(@"Deleting file for url %@", msg.messageText);
    // Delete the thumbnail before deleting the file, otherwise thumbnailURL will return nil
    // and the thumbnail won't be deleted
    if([info.mimeType hasPrefix:@"video/"])
    {
        DDLogVerbose(@"Deleting video thumbnail stored at %@", msg.fileInfo.thumbnailURL.path);
        [_fileManager removeItemAtPath:msg.fileInfo.thumbnailURL.path error:nil];
    }
    DDLogDebug(@"Deleting file in cache: %@", info.cacheFilePath);
    [_fileManager removeItemAtPath:info.cacheFilePath error:nil];
}

+(MLHandler*) prepareDataUpload:(NSData*) data
{
    return [self prepareDataUpload:data withFileExtension:@"dat"];
}

+(MLHandler*) prepareDataUpload:(NSData*) data withFileExtension:(NSString*) fileExtension
{
    DDLogInfo(@"Preparing for upload of NSData object: %@", data);
    
    //save file data to our document cache (temporary filename because the upload url is unknown yet)
    NSString* tempname = [NSString stringWithFormat:@"tmp.%@", [[NSUUID UUID] UUIDString]];
    NSError* error;
    NSString* file = [_documentCacheDir stringByAppendingPathComponent:tempname];
    DDLogDebug(@"Tempstoring data at %@", file);
    [data writeToFile:file options:NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:&error];
    if(error)
    {
        [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
        DDLogError(@"Failed to save NSData to file: %@", error);
        return $newHandler(self, errorCompletion, $ID(error));
    }
    [HelperTools configureFileProtectionFor:file];
    
    NSString* userFacingFilename = [NSString stringWithFormat:@"%@.%@", [[NSUUID UUID] UUIDString], fileExtension];
    return $newHandler(self, internalTmpFileUploadHandler,
        $ID(file),
        $ID(userFacingFilename),
        $ID(mimeType, [self getMimeTypeOfOriginalFile:userFacingFilename])
    );
}

+(MLHandler*) prepareFileUpload:(NSURL*) fileUrl
{
    DDLogInfo(@"Preparing for upload of file stored at %@", [fileUrl path]);
    
    //copy file to our document cache (temporary filename because the upload url is unknown yet)
    NSString* tempname = [NSString stringWithFormat:@"tmp.%@", [[NSUUID UUID] UUIDString]];
    NSError* error;
    NSString* file = [_documentCacheDir stringByAppendingPathComponent:tempname];
    DDLogDebug(@"Tempstoring file at %@", file);
    [_fileManager copyItemAtPath:[fileUrl path] toPath:file error:&error];
    if(error)
    {
        [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
        DDLogError(@"File upload failed: %@", error);
        return $newHandler(self, errorCompletion, $ID(error));
    }
    [HelperTools configureFileProtectionFor:file];
    
    return $newHandler(self, internalTmpFileUploadHandler,
        $ID(file),
        $ID(userFacingFilename, [fileUrl lastPathComponent]),
        $ID(mimeType, [self getMimeTypeOfOriginalFile:[fileUrl path]])
    );
}

+(MLHandler*) prepareUIImageUpload:(UIImage*) image
{
    DDLogInfo(@"Preparing for upload of image from UIImage object");
    double imageQuality = [[HelperTools defaultsDB] doubleForKey:@"ImageUploadQuality"];
    
    //copy file to our document cache (temporary filename because the upload url is unknown yet)
    NSString* tempname = [NSString stringWithFormat:@"tmp.%@", [[NSUUID UUID] UUIDString]];
    NSError* error;
    NSString* file = [_documentCacheDir stringByAppendingPathComponent:tempname];
    DDLogDebug(@"Tempstoring jpeg encoded file having quality %f at %@", imageQuality, file);
    NSData* imageData = UIImageJPEGRepresentation(image, imageQuality);
    //isaCloud: the share extension leaves the reduction to the main app (its time and memory budget is tight), see docs/analise-comprimir-imagens.md
    NSString* mode = [self imageCompressionMode];
    NSString* before = [NSString stringWithFormat:@"%.0fx%.0f px, %lu bytes at quality %.2f", image.size.width * image.scale, image.size.height * image.scale, (unsigned long) imageData.length, imageQuality];
    //a UIImage with an orientation other than "up" is drawn upright too (same normalization as the files with an orientation tag)
    BOOL normalize = image.imageOrientation != UIImageOrientationUp && ![mode isEqualToString:@"never"];
    if(![HelperTools isAppExtension] && (normalize || [self shouldCompressImageOfSize:imageData.length inMode:mode]))
    {
        //a photo smaller than the limit is only turned upright, never enlarged
        NSData* resizedData = [self resizedJPEGDataForImage:image maxPixelSize:ISACLOUD_IMAGE_MAX_PIXEL_SIZE quality:imageQuality];
        if(resizedData != nil)
        {
            DDLogInfo(@"Photo from memory reduced (mode %@): %@ -> %lu bytes, %@", mode, before, (unsigned long) resizedData.length, describeImageDataForLog(resizedData));
            imageData = resizedData;
        }
        else
            DDLogWarn(@"Could not resize the image, uploading it with the quality of the setting");
    }
    else
    {
        NSString* reason = [HelperTools isAppExtension] ? @"share extension, not reduced" : ([mode isEqualToString:@"never"] ? @"mode never" : @"under the limit");
        DDLogInfo(@"Photo from memory sent as it is (%@): %@", reason, before);
    }
    [imageData writeToFile:file options:NSDataWritingAtomic error:&error];
    if(error)
    {
        [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
        DDLogError(@"File upload failed: %@", error);
        return $newHandler(self, errorCompletion, $ID(error));
    }
    [HelperTools configureFileProtectionFor:file];
    
    return $newHandler(self, internalTmpFileUploadHandler,
        $ID(file),
        $ID(userFacingFilename, ([NSString stringWithFormat:@"%@.jpg", [[NSUUID UUID] UUIDString]])),
        $ID(mimeType, @"image/jpeg")
    );
}

//proxy to allow calling the completion with a (possibly) serialized error
$$class_handler(errorCompletion, $$ID(NSError*, error), $$ID(monal_upload_completion_t, completion))
    completion(nil, nil, nil, error);
$$

+(void) uploadFile:(NSURL*) fileUrl onAccount:(xmpp*) account withEncryption:(BOOL) encrypted andCompletion:(monal_upload_completion_t) completion
{
    DDLogInfo(@"Uploading file stored at %@", [fileUrl path]);
    //directly call internal file upload handler returned as MLHandler and bind our (non serializable) completion block to it
    $call([self prepareFileUpload:fileUrl], $ID(account), $BOOL(encrypted), $ID(completion));
}

+(void) uploadUIImage:(UIImage*) image onAccount:(xmpp*) account withEncryption:(BOOL) encrypted andCompletion:(monal_upload_completion_t) completion
{
    DDLogInfo(@"Uploading image from UIImage object");
    //directly call internal file upload handler returned as MLHandler and bind our (non serializable) completion block to it
    $call([self prepareUIImageUpload:image], $ID(account), $BOOL(encrypted), $ID(completion));
}

#pragma mark - isaCloud: photo reduction before the upload

+(NSString*) imageCompressionMode
{
    //"large" is the default (also when the setting is missing, e.g. in tests)
    return [[HelperTools defaultsDB] stringForKey:@"imageCompressionMode"] ?: @"large";
}

+(BOOL) shouldCompressImageOfSize:(unsigned long long) bytes inMode:(NSString*) mode
{
    if([mode isEqualToString:@"always"])
        return YES;
    if([mode isEqualToString:@"large"])
        return bytes > ISACLOUD_IMAGE_COMPRESSION_LARGE_BYTES;
    //"never" (and anything unknown): the original is sent
    return NO;
}

+(BOOL) imageFileNeedsCompression:(NSURL*) fileUrl
{
    return [self imageFileNeedsCompression:fileUrl asFilename:fileUrl.lastPathComponent];
}

+(BOOL) imageFileNeedsCompression:(NSURL*) fileUrl asFilename:(NSString*) filename
{
    //the type comes from the name the file is sent with (a temporary file of the outbox has no extension of its own)
    //only still images are reduced: an animated gif would lose its animation, and other files are sent as they are
    UTType* type = [UTType typeWithFilenameExtension:filename.pathExtension];
    if(type == nil || ![type conformsToType:UTTypeImage] || [type conformsToType:UTTypeGIF])
        return NO;
    NSString* mode = [self imageCompressionMode];
    //"never" sends the original, rotation tag included
    if([mode isEqualToString:@"never"])
        return NO;
    //a photo with an orientation tag is always normalized (its pixels turned upright, the tag removed), whatever its size,
    //because receivers disagree on how to read the tag (e.g. the Android app shows mirrored selfies lying down)
    if(imageFileHasOrientationTag(fileUrl))
        return YES;
    NSDictionary* attributes = [_fileManager attributesOfItemAtPath:fileUrl.path error:nil];
    return [self shouldCompressImageOfSize:attributes.fileSize inMode:mode];
}

+(void) compressImageFileIfNeeded:(NSURL*) fileUrl completion:(void (^)(NSURL* resultUrl)) completion
{
    [self compressImageFileIfNeeded:fileUrl asFilename:fileUrl.lastPathComponent completion:completion];
}

+(void) compressImageFileIfNeeded:(NSURL*) fileUrl asFilename:(NSString*) filename completion:(void (^)(NSURL* resultUrl)) completion
{
    //the work runs on a utility queue, never on the main thread; if it fails, the original file is sent
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSURL* resultUrl = fileUrl;
        if([self imageFileNeedsCompression:fileUrl asFilename:filename])
        {
            NSURL* resizedUrl = [self resizedImageFileForUrl:fileUrl maxPixelSize:ISACLOUD_IMAGE_MAX_PIXEL_SIZE quality:[[HelperTools defaultsDB] doubleForKey:@"ImageUploadQuality"]];
            if(resizedUrl != nil)
                resultUrl = resizedUrl;
            else
                DDLogWarn(@"Could not resize %@, sending the original file", fileUrl.lastPathComponent);
        }
        completion(resultUrl);
    });
}

+(NSURL*) resizedImageFileForUrl:(NSURL*) fileUrl maxPixelSize:(CGFloat) maxSize quality:(double) quality
{
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef) fileUrl, NULL);
    if(source == NULL)
    {
        DDLogError(@"Could not read image at %@", fileUrl.path);
        return nil;
    }
    //a photo smaller than the limit is only turned upright, never enlarged
    NSDictionary* props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CGFloat longestSide = MAX([props[(__bridge NSString*) kCGImagePropertyPixelWidth] doubleValue], [props[(__bridge NSString*) kCGImagePropertyPixelHeight] doubleValue]);
    if(longestSide > 0 && longestSide < maxSize)
        maxSize = longestSide;
    //the thumbnail is the image scaled so its longest side is maxSize, with the EXIF orientation applied to the pixels
    //(the photo keeps its pixels in sensor orientation and its rotation only in the metadata)
    NSDictionary* options = @{
        (__bridge NSString*) kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString*) kCGImageSourceThumbnailMaxPixelSize: @(maxSize),
        (__bridge NSString*) kCGImageSourceCreateThumbnailWithTransform: @YES,
    };
    NSString* before = [NSString stringWithFormat:@"%llu bytes, %@", [[_fileManager attributesOfItemAtPath:fileUrl.path error:nil] fileSize], describeImageSource(source)];
    CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef) options);
    CFRelease(source);
    if(thumbnail == NULL)
    {
        DDLogError(@"Could not create thumbnail of %@", fileUrl.path);
        return nil;
    }
    CGImageRef flatImage = createWhiteBackedCopyOfImage(thumbnail);
    CGImageRelease(thumbnail);
    if(flatImage == NULL)
        return nil;

    //the new JPEG is written from the pixels only: no orientation and no other metadata (e.g. location) are copied
    NSMutableData* jpegData = [NSMutableData new];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef) jpegData, CFSTR("public.jpeg"), 1, NULL);
    if(destination == NULL)
    {
        CGImageRelease(flatImage);
        return nil;
    }
    CGImageDestinationAddImage(destination, flatImage, (__bridge CFDictionaryRef) @{
        (__bridge NSString*) kCGImageDestinationLossyCompressionQuality: @(quality),
    });
    BOOL finalized = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    CGImageRelease(flatImage);
    if(!finalized)
    {
        DDLogError(@"Could not encode resized image of %@", fileUrl.path);
        return nil;
    }

    //one folder per resized copy, so the file keeps the name of the original (it is the name shown to the receiver)
    NSString* folder = [_documentCacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"resized.%@", [[NSUUID UUID] UUIDString]]];
    NSString* file = [folder stringByAppendingPathComponent:[[fileUrl.lastPathComponent stringByDeletingPathExtension] stringByAppendingPathExtension:@"jpg"]];
    NSError* error;
    [_fileManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error];
    if(!error)
        [jpegData writeToFile:file options:NSDataWritingAtomic error:&error];
    if(error)
    {
        [_fileManager removeItemAtPath:folder error:nil];
        DDLogError(@"Could not save resized image: %@", error);
        return nil;
    }
    [HelperTools configureFileProtectionFor:file];
    DDLogInfo(@"Photo %@ reduced (mode %@): %@ -> %lu bytes, %@", fileUrl.lastPathComponent, [self imageCompressionMode], before, (unsigned long) jpegData.length, describeImageDataForLog(jpegData));
    return [NSURL fileURLWithPath:file];
}

//isaCloud: logs an attachment that is sent as it is (the reason and, for images, the size and pixels), so the photo tests can be read from the log
+(void) logFileNotReduced:(NSURL*) fileUrl
{
    NSString* mode = [self imageCompressionMode];
    UTType* type = [UTType typeWithFilenameExtension:fileUrl.pathExtension];
    BOOL isStillImage = type != nil && [type conformsToType:UTTypeImage] && ![type conformsToType:UTTypeGIF];
    NSString* reason;
    if(type == nil || ![type conformsToType:UTTypeImage])
        reason = @"not an image";
    else if([type conformsToType:UTTypeGIF])
        reason = @"GIF, never reduced";
    else if([mode isEqualToString:@"never"])
        reason = @"mode never";
    else
        reason = @"under the limit";
    unsigned long long bytes = [[_fileManager attributesOfItemAtPath:fileUrl.path error:nil] fileSize];
    DDLogInfo(@"Attachment %@ sent as it is (%@): %llu bytes%@", fileUrl.lastPathComponent, reason, bytes, isStillImage ? [NSString stringWithFormat:@", %@", describeImageFileForLog(fileUrl)] : @"");
}

#pragma mark - isaCloud: video conversion before the upload

//the four character code of a codec ("avc1", "hvc1"...), only for the video log lines
static NSString* fourCCStringForLog(FourCharCode code)
{
    char chars[5] = {
        (char) ((code >> 24) & 0xFF),
        (char) ((code >> 16) & 0xFF),
        (char) ((code >> 8) & 0xFF),
        (char) (code & 0xFF),
        0,
    };
    NSString* result = [NSString stringWithCString:chars encoding:NSASCIIStringEncoding];
    return result ?: @"unknown";
}

//true if the file has a location (GPS) in its common metadata
static BOOL videoAssetHasLocationForLog(AVAsset* asset)
{
    for(AVMetadataItem* item in asset.commonMetadata)
        if([item.commonKey isEqualToString:AVMetadataCommonKeyLocation])
            return YES;
    return NO;
}

//size, duration, pixels, codec, frame rate and location of a video, only for the video log lines
static NSString* describeVideoAssetForLog(AVURLAsset* asset, unsigned long long bytes)
{
    AVAssetTrack* track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    NSString* codec = @"none";
    CGSize size = CGSizeZero;
    float fps = 0;
    if(track != nil)
    {
        size = track.naturalSize;
        fps = track.nominalFrameRate;
        CMFormatDescriptionRef description = (__bridge CMFormatDescriptionRef) track.formatDescriptions.firstObject;
        if(description != NULL)
            codec = fourCCStringForLog(CMFormatDescriptionGetMediaSubType(description));
    }
    return [NSString stringWithFormat:@"%llu bytes, %.1f s, %.0fx%.0f px, codec %@, %.1f fps, gps=%@",
        bytes, CMTimeGetSeconds(asset.duration), size.width, size.height, codec, fps, videoAssetHasLocationForLog(asset) ? @"sim" : @"não"];
}

+(NSString*) videoCompressionMode
{
    //"480" is the default (also when the setting is missing, e.g. in tests)
    return [[HelperTools defaultsDB] stringForKey:@"videoCompressionMode"] ?: @"480";
}

+(BOOL) videoFileNeedsCompression:(NSURL*) fileUrl
{
    //"original" sends the video as it is; a small video is not worth the time of a conversion
    if([[self videoCompressionMode] isEqualToString:@"original"])
        return NO;
    NSDictionary* attributes = [_fileManager attributesOfItemAtPath:fileUrl.path error:nil];
    return attributes.fileSize > ISACLOUD_VIDEO_KEEP_BYTES;
}

static NSURL* convertVideoFileForAsset(AVURLAsset* asset, NSURL* fileUrl);

+(void) compressVideoFileIfNeeded:(NSURL*) fileUrl completion:(void (^)(NSURL* _Nullable resultUrl, NSString* _Nullable reason)) completion
{
    //the work runs on a utility queue, never on the main thread; a failed conversion sends the original file
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString* mode = [self videoCompressionMode];
        AVURLAsset* asset = [AVURLAsset URLAssetWithURL:fileUrl options:nil];
        unsigned long long bytes = [[_fileManager attributesOfItemAtPath:fileUrl.path error:nil] fileSize];
        DDLogInfo(@"Video before conversion (mode %@): %@", mode, describeVideoAssetForLog(asset, bytes));

        //a longer video is not sent at all: the upload limit is 150 MB, and 480p of 4 minutes is already about 123 MB
        if(CMTimeGetSeconds(asset.duration) > ISACLOUD_VIDEO_MAX_SECONDS)
        {
            DDLogInfo(@"Video result too_long (mode %@): not sent", mode);
            completion(nil, @"too_long");
            return;
        }
        if(![self videoFileNeedsCompression:fileUrl])
        {
            NSString* result = [mode isEqualToString:@"original"] ? @"kept_original_mode" : @"kept_small";
            DDLogInfo(@"Video result %@ (mode %@): sent as it is, %@, conversion 0.0 s", result, mode, describeVideoAssetForLog(asset, bytes));
            completion(fileUrl, result);
            return;
        }
        CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
        NSURL* convertedUrl = convertVideoFileForAsset(asset, fileUrl);
        CFAbsoluteTime seconds = CFAbsoluteTimeGetCurrent() - started;
        if(convertedUrl == nil)
        {
            DDLogInfo(@"Video result kept_original_after_failure (mode %@): sent as it is, %@, conversion %.1f s", mode, describeVideoAssetForLog(asset, bytes), seconds);
            completion(fileUrl, @"kept_original_after_failure");
            return;
        }
        AVURLAsset* convertedAsset = [AVURLAsset URLAssetWithURL:convertedUrl options:nil];
        unsigned long long convertedBytes = [[_fileManager attributesOfItemAtPath:convertedUrl.path error:nil] fileSize];
        DDLogInfo(@"Video result converted (mode %@): %@ -> %@, conversion %.1f s", mode, describeVideoAssetForLog(asset, bytes), describeVideoAssetForLog(convertedAsset, convertedBytes), seconds);
        completion(convertedUrl, @"converted");
    });
}

//exports the video at 480p (H.264 + AAC in an MP4) into a folder of its own in the temporary directory; the caller removes the folder
//returns nil if the conversion fails or takes too long (the folder is removed then)
static NSURL* convertVideoFileForAsset(AVURLAsset* asset, NSURL* fileUrl)
{
    NSString* folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"video-%@", [[NSUUID UUID] UUIDString]]];
    NSString* file = [folder stringByAppendingPathComponent:[[fileUrl.lastPathComponent stringByDeletingPathExtension] stringByAppendingPathExtension:@"mp4"]];
    NSError* error;
    [_fileManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error];
    if(error)
    {
        DDLogError(@"Could not create folder for the converted video: %@", error.localizedDescription);
        return nil;
    }
    AVAssetExportSession* session = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPreset640x480];
    if(session == nil)
    {
        DDLogError(@"480p export is not available for this video");
        [_fileManager removeItemAtPath:folder error:nil];
        return nil;
    }
    session.outputURL = [NSURL fileURLWithPath:file];
    session.outputFileType = AVFileTypeMPEG4;
    session.shouldOptimizeForNetworkUse = YES;
    //the location (GPS) and the other metadata that is not needed to play the video are left out
    session.metadataItemFilter = [AVMetadataItemFilter metadataItemFilterForSharing];
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    //the export is started and waited for on this utility queue (the video is only converted while the app is open)
    [session exportAsynchronouslyWithCompletionHandler:^{
        dispatch_semaphore_signal(finished);
    }];
    long timedOut = dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, ISACLOUD_VIDEO_CONVERSION_TIMEOUT * NSEC_PER_SEC));
    if(timedOut)
        [session cancelExport];
    if(timedOut || session.status != AVAssetExportSessionStatusCompleted)
    {
        //the error text can contain the file name, so only its code is logged
        DDLogError(@"Video conversion failed (status %ld, error code %ld, timed out %d)", (long) session.status, (long) session.error.code, (int) timedOut);
        [_fileManager removeItemAtPath:folder error:nil];
        return nil;
    }
    [HelperTools configureFileProtectionFor:file];
    return [NSURL fileURLWithPath:file];
}

+(NSData*) resizedJPEGDataForImage:(UIImage*) image maxPixelSize:(CGFloat) maxSize quality:(double) quality
{
    //image.size already has the orientation applied; drawing it applies the orientation to the pixels of the new image
    CGSize pixels = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
    CGFloat longestSide = MAX(pixels.width, pixels.height);
    if(longestSide <= 0)
        return nil;
    CGFloat factor = MIN((CGFloat) 1.0, maxSize / longestSide);
    CGSize target = CGSizeMake(round(pixels.width * factor), round(pixels.height * factor));

    UIGraphicsImageRendererFormat* format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    format.opaque = YES;
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
    UIImage* resized = [renderer imageWithActions:^(UIGraphicsImageRendererContext* context __unused) {
        //white behind transparent parts (a JPEG has no alpha)
        [[UIColor whiteColor] setFill];
        UIRectFill(CGRectMake(0, 0, target.width, target.height));
        [image drawInRect:CGRectMake(0, 0, target.width, target.height)];
    }];
    return UIImageJPEGRepresentation(resized, quality);
}

//returns a new image (the caller releases it) of the same pixels, with white behind transparent parts
static CGImageRef createWhiteBackedCopyOfImage(CGImageRef image) CF_RETURNS_RETAINED;
static CGImageRef createWhiteBackedCopyOfImage(CGImageRef image)
{
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, colorSpace, (CGBitmapInfo) kCGImageAlphaNoneSkipLast);
    CGColorSpaceRelease(colorSpace);
    if(context == NULL)
        return NULL;
    CGRect rect = CGRectMake(0, 0, (CGFloat) width, (CGFloat) height);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, rect);
    CGContextDrawImage(context, rect, image);
    CGImageRef result = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return result;
}

//isaCloud: "WxH px, EXIF orientation N" of an image (the orientation is what the photo's pixels still have to be rotated by)
static NSString* describeImageSource(CGImageSourceRef source)
{
    NSDictionary* props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    NSNumber* width = props[(__bridge NSString*) kCGImagePropertyPixelWidth];
    NSNumber* height = props[(__bridge NSString*) kCGImagePropertyPixelHeight];
    NSNumber* orientation = props[(__bridge NSString*) kCGImagePropertyOrientation];
    return [NSString stringWithFormat:@"%@x%@ px, EXIF orientation %@", width ?: @"?", height ?: @"?", orientation ?: @"none"];
}

static NSString* describeImageDataForLog(NSData* data)
{
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef) data, NULL);
    if(source == NULL)
        return @"unreadable image";
    NSString* result = describeImageSource(source);
    CFRelease(source);
    return result;
}

//isaCloud: YES when the file has an EXIF orientation other than 1 ("up"), i.e. its pixels are not stored upright
static BOOL imageFileHasOrientationTag(NSURL* fileUrl)
{
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef) fileUrl, NULL);
    if(source == NULL)
        return NO;
    NSDictionary* props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CFRelease(source);
    NSNumber* orientation = props[(__bridge NSString*) kCGImagePropertyOrientation];
    return orientation != nil && orientation.integerValue != 1;
}

static NSString* describeImageFileForLog(NSURL* fileUrl)
{
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef) fileUrl, NULL);
    if(source == NULL)
        return @"unreadable image";
    NSString* result = describeImageSource(source);
    CFRelease(source);
    return result;
}

+(void) doStartupCleanup
{
    //delete leftover tmp files older than 1 day
    NSDate* now = [NSDate date];
    NSArray* directoryContents = [_fileManager contentsOfDirectoryAtPath:_documentCacheDir error:nil];
    NSPredicate* filter = [NSPredicate predicateWithFormat:@"self BEGINSWITH 'tmp.'"];
    for(NSString* file in [directoryContents filteredArrayUsingPredicate:filter])
    {
        NSString* filePath = [_documentCacheDir stringByAppendingPathComponent:file];
        NSURL* fileUrl = [NSURL fileURLWithPath:filePath];
        NSDate* fileDate;
        NSError* error;
        [fileUrl getResourceValue:&fileDate forKey:NSURLContentModificationDateKey error:&error];
        if(!error && [now timeIntervalSinceDate:fileDate]/86400 > 1)
        {
            DDLogInfo(@"Deleting leftover tmp file at %@", filePath);
            [_fileManager removeItemAtPath:filePath error:nil];
        }
    }
    //isaCloud: resized photos are removed by the upload that made them; the ones left here were cut short by a force-close
    //(no upload is running yet at startup, and the share extension never resizes)
    NSPredicate* resizedFilter = [NSPredicate predicateWithFormat:@"self BEGINSWITH 'resized.'"];
    for(NSString* folder in [directoryContents filteredArrayUsingPredicate:resizedFilter])
    {
        DDLogInfo(@"Deleting leftover resized photo folder %@", folder);
        [_fileManager removeItemAtPath:[_documentCacheDir stringByAppendingPathComponent:folder] error:nil];
    }
    // delete any file preview hardlinks that didn't get deleted normally
    // e.g. due to a force-close while the preview is open
    NSString* previewsDirectory = [HelperTools filePreviewHardlinksDirectory];
    [_fileManager removeItemAtPath:previewsDirectory error:nil];
}

#pragma mark - internal methods

+(NSString*) retrieveCacheFilePathForUrl:(NSString*) url andMimeType:(NSString*) mimeType
{
    NSString* urlPart = [HelperTools hexadecimalString:[HelperTools sha256:[url dataUsingEncoding:NSUTF8StringEncoding]]];
    if(mimeType)
    {
        NSString* mimePart = [HelperTools hexadecimalString:[mimeType dataUsingEncoding:NSUTF8StringEncoding]];
        
        //the cache filename consists of a hash of the upload url (in hex) followed of the file mimetype (also in hex) as file extension
        NSString* cacheFilePath = [_documentCacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", urlPart, mimePart]];
        
        //file having the supplied mimeType exists
        if([_fileManager fileExistsAtPath:cacheFilePath])
            return cacheFilePath;
    }

    //nothing found
    DDLogVerbose(@"Could not find cache file for url '%@' having mime type '%@'...", url, mimeType);
    return nil;
}

+(NSString*) calculateCacheFilePathForNewUrl:(NSString*) url andMimeType:(NSString*) mimeType
{
    //the cache filename consists of a hash of the upload url (in hex) followed of the file mimetype (also in hex) as file extension
    NSString* urlPart = [HelperTools hexadecimalString:[HelperTools sha256:[url dataUsingEncoding:NSUTF8StringEncoding]]];
    NSString* mimePart = [HelperTools hexadecimalString:[mimeType dataUsingEncoding:NSUTF8StringEncoding]];
    return [_documentCacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", urlPart, mimePart]];
}

+(NSString*) genCanonicalUrl:(NSString*) url
{
    NSURLComponents* urlComponents = [NSURLComponents componentsWithString:url];
    if(!urlComponents)
    {
        DDLogWarn(@"Failed to get url components, returning empty url!");
        return @"";
    }
    if([[urlComponents.scheme lowercaseString] isEqualToString:@"aesgcm"])
        urlComponents.scheme = @"https";
    if(![[urlComponents.scheme lowercaseString] isEqualToString:@"https"])
    {
        DDLogWarn(@"Failed to get url components, returning empty url!");
        return @"";
    }
    urlComponents.fragment = nil;       //make sure we don't leak urlfragments to upload server
    return urlComponents.string;
}

+(NSString*) getMimeTypeOfOriginalFile:(NSString*) file
{
    UTType* type = [UTType typeWithTag:[file pathExtension] tagClass:UTTagClassFilenameExtension conformingToType:UTTypeData];
    if(type.preferredMIMEType == nil)
        return @"application/octet-stream";
    return type.preferredMIMEType;
}

+(void) setErrorType:(NSString*) errorType andErrorText:(NSString*) errorText forMessage:(MLMessage*) msg
{
    //update db
    [[DataLayer sharedInstance]
        setMessageId:msg.messageId
        andJid:msg.buddyName
        errorType:errorType
        errorReason:errorText
    ];
    
    //inform chatview of error
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalMessageErrorNotice object:nil userInfo:@{
        kMessageId: msg.messageId,
        @"jid": msg.buddyName,
        @"errorType": errorType,
        @"errorReason": errorText
    }];
}

$$class_handler(internalTmpFileUploadHandler, $$ID(NSString*, file), $$ID(NSString*, userFacingFilename), $$ID(NSString*, mimeType), $$ID(xmpp*, account), $$BOOL(encrypted), $$ID(monal_upload_completion_t, completion))
    NSError* error;
    
    //make sure we don't upload the same tmpfile twice (should never happen anyways)
    @synchronized(_stateSyncObject)
    {
        if([self isFileAtPathInTransfer:file])
        {
            error = [NSError errorWithDomain:@"MonalError" code:0 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Already uploading this content, ignoring", @"")}];
            DDLogError(@"Already uploading this content, ignoring %@", file);
            [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
            return completion(nil, nil, nil, error);
        }
        [self addTransfer:file];
    }
    
    //TODO: allow real file based transfers instead of NSData based transfers
    DDLogDebug(@"Reading file data into NSData object");
    NSData* fileData = [[NSData alloc] initWithContentsOfFile:file options:0 error:&error];
    if(error)
    {
        [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
        [self markAsComplete:file];
        DDLogError(@"File upload failed: %@", error);
        return completion(nil, nil, nil, error);
    }
    
    //encrypt data (TODO: do this in a streaming fashion, e.g. from file to tmpfile and stream this tmpfile via http afterwards)
    MLEncryptedPayload* encryptedPayload;
    if(encrypted)
    {
        DDLogInfo(@"Encrypting file data before upload");
        encryptedPayload = [AESGcm encrypt:fileData keySize:32];
        if(encryptedPayload && encryptedPayload.body != nil)
        {
            NSMutableData* encryptedData = [encryptedPayload.body mutableCopy];
            [encryptedData appendData:encryptedPayload.authTag];
            fileData = encryptedData;
        }
        else
        {
            NSError* error = [NSError errorWithDomain:@"MonalError" code:0 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to encrypt file", @"")}];
            [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
            [self markAsComplete:file];
            DDLogError(@"File upload failed: %@", error);
            return completion(nil, nil, nil, error);
        }
    }
    
    MLAssert(userFacingFilename != nil, @"userFacingFilename should never be nil!");

    //make sure we don't leak information about encrypted files
    NSString* sendMimeType = mimeType;
    if(encrypted)
    {
        sendMimeType = @"application/octet-stream";
        userFacingFilename = [NSString stringWithFormat:@"%@.%@", [[NSUUID UUID] UUIDString], userFacingFilename.pathExtension];
    }
    
    MLAssert(fileData != nil, @"fileData should never be nil!");
    MLAssert(sendMimeType != nil, @"sendMimeType should never be nil!");
    
    DDLogDebug(@"Requesting file upload slot for mimeType %@", sendMimeType);
    [account requestHTTPSlotWithParams:@{
        @"data":fileData,
        @"fileName":userFacingFilename,
        @"contentType":sendMimeType
    } andCompletion:^(NSString* url, NSError* error) {
        if(error)
        {
            [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
            [self markAsComplete:file];
            DDLogError(@"File upload failed: %@", error);
            return completion(nil, nil, nil, error);
        }
        
        NSURLComponents* urlComponents = [NSURLComponents componentsWithString:url];
        if(url && urlComponents)
        {
            //build aesgcm url containing "aesgcm" url-scheme and IV and AES-key in urlfragment
            if(encrypted)
            {
                urlComponents.scheme = @"aesgcm";
                urlComponents.fragment = [NSString stringWithFormat:@"%@%@",
                                        [HelperTools hexadecimalString:encryptedPayload.iv],
                                        //extract real aes key without authtag (32 bytes = 256bit) (conversations compatibility)
                                        [HelperTools hexadecimalString:[encryptedPayload.key subdataWithRange:NSMakeRange(0, 32)]]];
                url = urlComponents.string;
            }
            
            //ignore upload if account was already removed
            if([[MLXMPPManager sharedInstance] getEnabledAccountForID:account.accountID] == nil)
            {
                NSError* error = [NSError errorWithDomain:@"MonalError" code:0 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to upload file: account was removed", @"")}];
                [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
                [self markAsComplete:file];
                DDLogError(@"File upload failed: %@", error);
                return completion(nil, nil, nil, error);
            }
            
            //move the tempfile to our cache location
            NSString* cacheFilePath = [self calculateCacheFilePathForNewUrl:url andMimeType:mimeType];
            DDLogInfo(@"Moving (possibly encrypted) file to our document cache at %@", cacheFilePath);
            [_fileManager moveItemAtPath:file toPath:cacheFilePath error:&error];
            if(error)
            {
                NSError* error = [NSError errorWithDomain:@"MonalError" code:0 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to move uploaded file to file cache directory", @"")}];
                [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
                [self markAsComplete:file];
                DDLogError(@"File upload failed: %@", error);
                return completion(nil, nil, nil, error);
            }
            [HelperTools configureFileProtectionFor:cacheFilePath];
            
            [self markAsComplete:file];
            DDLogInfo(@"URL for download: %@", url);
            return completion(url, mimeType, [NSNumber numberWithInteger:fileData.length], nil);
        }
        else
        {
            NSError* error = [NSError errorWithDomain:@"MonalError" code:0 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to parse URL returned by HTTP upload server", @"")}];
            [_fileManager removeItemAtPath:file error:nil];      //remove temporary file
            [self markAsComplete:file];
            DDLogError(@"File upload failed: %@", error);
            return completion(nil, nil, nil, error);
        }
    }];
$$

#pragma mark - NSURLSessionDelegate

-(void) URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession*) session
{
    //notify about finished background fetch (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
    //this will be used by the mainapp app delegate to call the backgroundURLSessionCompletionHandler callback
    DDLogVerbose(@"Posting kMonalFiletransferEventsFinished notification now...");
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalFiletransferEventsFinished object:nil];
}

-(void) URLSession:(NSURLSession*) session downloadTask:(NSURLSessionDownloadTask*) downloadTask didFinishDownloadingToURL:(NSURL*) location
{
    NSDictionary* associatedData = [HelperTools unserializeData:[HelperTools dataWithHexString:downloadTask.taskDescription]];
    @synchronized(_stateSyncObject) {
        [_expectedDownloadSizes removeObjectForKey:associatedData[@"url"]];
        [[self class] storeState];
    }
    DDLogVerbose(@"Background filetransfer completed: %@", associatedData);
    $call(associatedData[@"handler"], $ID(location), $ID(response, downloadTask.response));
}

-(void) URLSession:(NSURLSession*) session task:(NSURLSessionTask*) task didCompleteWithError:(NSError* _Nullable) error
{
    //we only need to forward errors, everything else was already forwarded by URLSession:downloadTask:didFinishDownloadingToURL:
    if(error != nil)
    {
        NSDictionary* associatedData = [HelperTools unserializeData:[HelperTools dataWithHexString:task.taskDescription]];
        DDLogVerbose(@"Background filetransfer %@ failed with error: %@", associatedData, error);
        $call(associatedData[@"handler"], $ID(error));
    }
}

-(void) URLSession:(NSURLSession*) session downloadTask:(NSURLSessionDownloadTask*) downloadTask didWriteData:(int64_t) bytesWritten totalBytesWritten:(int64_t) totalBytesWritten totalBytesExpectedToWrite:(int64_t) totalBytesExpectedToWrite
{
    NSDictionary* associatedData = [HelperTools unserializeData:[HelperTools dataWithHexString:downloadTask.taskDescription]];
    MLMessage* msg = [MLMessage createMessageFromHistoryID:associatedData[@"historyId"]];
    xmpp* account = [[MLXMPPManager sharedInstance] getEnabledAccountForID:msg.accountID];
    NSNumber* expectedSize;
    @synchronized(_stateSyncObject) {
        expectedSize = _expectedDownloadSizes[associatedData[@"url"]];
    }
    if(expectedSize != nil && expectedSize.longLongValue != -1)
    {
        //only allow for a maximum of 512KiB of extra data
        if(totalBytesWritten >= expectedSize.longLongValue + 512 * 1024)
            return [downloadTask cancel];
        
        //notify about download progress, but don't send out update notices for already deleted accounts
        if(account != nil)
            dispatch_async(dispatch_get_main_queue(), ^{
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalMessageFiletransferUpdateNotice object:account userInfo:@{
                    @"message": msg,
                    @"progress": @((double)totalBytesWritten / (double)expectedSize.longLongValue),
                }];
            });
    }
}

-(void) URLSession:(NSURLSession*) session task:(NSURLSessionTask*) task didSendBodyData:(int64_t) bytesSent totalBytesSent:(int64_t) totalBytesSent totalBytesExpectedToSend:(int64_t) totalBytesExpectedToSend
{
    //this only handles upload progress, download progress is handled in another delegate method (see above)
    if([task isKindOfClass:NSURLSessionDownloadTask.class])
        return;
    
    //notify about download progress if we know the size (should be always true)
    if(totalBytesExpectedToSend > 0)
    {
        NSDictionary* associatedData = [HelperTools unserializeData:[HelperTools dataWithHexString:task.taskDescription]];
        MLMessage* msg = [MLMessage createMessageFromHistoryID:associatedData[@"historyId"]];
        xmpp* account = [[MLXMPPManager sharedInstance] getEnabledAccountForID:msg.accountID];
        if(account != nil)      //don't send out update notices for already deleted accounts
            dispatch_async(dispatch_get_main_queue(), ^{
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalMessageFiletransferUpdateNotice object:account userInfo:@{
                    @"message": msg,
                    @"progress": @((double)totalBytesSent / (double)totalBytesExpectedToSend),
                }];
            });
    }
}

@end
