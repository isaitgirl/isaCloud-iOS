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
+(nullable NSURL*) resizedImageFileForUrl:(NSURL*) fileUrl maxPixelSize:(CGFloat) maxSize quality:(double) quality;
+(nullable NSData*) resizedJPEGDataForImage:(UIImage*) image maxPixelSize:(CGFloat) maxSize quality:(double) quality;

@end

NS_ASSUME_NONNULL_END
