//
//  MLFiletransfer.h
//  monalxmpp
//
//  Created by Thilo Molitor on 12.11.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class MLMessage;
@class xmpp;

@interface MLFiletransfer : NSObject<NSURLSessionDownloadDelegate>
@property (class, readonly) BOOL isIdle;

+(BOOL) isIdle;
+(void) doStartupCleanup;
+(void) checkMimeTypeAndSizeForHistoryID:(NSNumber*) historyId;
+(void) downloadFileForHistoryID:(NSNumber*) historyId;
+(void) deleteFileForMessage:(MLMessage* _Nullable) msg;
+(MLHandler*) prepareDataUpload:(NSData*) data;
+(MLHandler*) prepareDataUpload:(NSData*) data withFileExtension:(NSString*) fileExtension;
+(MLHandler*) prepareFileUpload:(NSURL*) fileUrl;
+(MLHandler*) prepareUIImageUpload:(UIImage*) image;
//isaCloud: logs an attachment that is sent without reduction (reason, size and pixels), for the photo tests
+(void) logFileNotReduced:(NSURL*) fileUrl;
//isaCloud: C20, stores the state kept while the app was frozen (called on kMonalUnfrozen and when the app comes back from a freeze)
+(void) isaCloudStoreStateAfterUnfreeze;
+(void) uploadFile:(NSURL*) fileUrl onAccount:(xmpp*) account withEncryption:(BOOL) encrypted andCompletion:(void (^)(NSString* _Nullable url, NSString* _Nullable mimeType, NSNumber* _Nullable size, NSError* _Nullable error)) completion;
+(void) uploadUIImage:(UIImage*) image onAccount:(xmpp*) account withEncryption:(BOOL) encrypted andCompletion:(void (^)(NSString* _Nullable url, NSString* _Nullable mimeType, NSNumber* _Nullable size, NSError* _Nullable error)) completion;
+(void) hardlinkFileForMessage:(MLMessage*) msg;
+(BOOL) isFileForHistoryIdInTransfer:(NSNumber*) historyId;
+(NSString*) getMimeTypeOfOriginalFile:(NSString*) file;

//isaCloud: photo reduction before the upload (docs/analise-comprimir-imagens.md); the mode is the "imageCompressionMode" setting
+(NSString*) imageCompressionMode;
+(BOOL) shouldCompressImageOfSize:(unsigned long long) bytes inMode:(NSString*) mode;
+(BOOL) imageFileNeedsCompression:(NSURL*) fileUrl;
+(void) compressImageFileIfNeeded:(NSURL*) fileUrl completion:(void (^)(NSURL* resultUrl)) completion;
+(BOOL) imageFileNeedsCompression:(NSURL*) fileUrl asFilename:(NSString*) filename;
+(void) compressImageFileIfNeeded:(NSURL*) fileUrl asFilename:(NSString*) filename completion:(void (^)(NSURL* resultUrl)) completion;
+(nullable NSURL*) resizedImageFileForUrl:(NSURL*) fileUrl maxPixelSize:(CGFloat) maxSize quality:(double) quality;
+(nullable NSData*) resizedJPEGDataForImage:(UIImage*) image maxPixelSize:(CGFloat) maxSize quality:(double) quality;

//isaCloud: video conversion before the upload (docs/analise-comprimir-videos.md); the mode is the "videoCompressionMode" setting ("480" or "original")
+(NSString*) videoCompressionMode;
+(BOOL) videoFileNeedsCompression:(NSURL*) fileUrl;
//isaCloud: size the video will have when uploaded: the file size if it is sent as it is, else the 480p estimate (duration x 490000 bytes/s)
+(int64_t) estimatedUploadBytesForVideo:(NSURL*) fileUrl;
//isaCloud: checks a video before it is sent (gallery and camera videos): YES if its estimated upload is bigger than uploadSize (reason "over_server_limit"); uploadSize 0 (unknown) always gives NO
+(BOOL) videoIsTooLargeForServer:(NSURL*) fileUrl uploadSize:(NSInteger) uploadSize reason:(NSString* _Nullable* _Nullable) reason;
//isaCloud: the server's limit as the people who set it write it: in MiB (200 MiB is 209715200 bytes), e.g. "200 MiB" or "1.5 MiB"
+(NSString*) serverLimitTextForBytes:(NSInteger) bytes;
//the reason is the result: "converted", "kept_small", "kept_original_mode" or "kept_original_after_failure"; the url is never nil
+(void) compressVideoFileIfNeeded:(NSURL*) fileUrl completion:(void (^)(NSURL* _Nullable resultUrl, NSString* _Nullable reason)) completion;

@end

NS_ASSUME_NONNULL_END
