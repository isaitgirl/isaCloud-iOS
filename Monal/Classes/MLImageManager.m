//
//  MLImageManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/16/13.
//
//

#import <monalxmpp/MLImageManager.h>
#import <monalxmpp/MLXMPPManager.h>
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/DataLayer.h>
#import "AESGcm.h"
#import <monalxmpp/UIColor+Extension.h>
#import "GeneratedAssetSymbols.h"


@interface MLImageManager()
@property (nonatomic, strong) NSCache* iconCache;
@property (nonatomic, strong) NSString* documentsDirectory;
@property (nonatomic, strong) NSCache* backgroundCache;
@end

@implementation MLImageManager

#pragma mark initilization

+(MLImageManager*) sharedInstance
{
    static dispatch_once_t once;
    static MLImageManager* sharedInstance;
    dispatch_once(&once, ^{
        DDLogVerbose(@"Creating shared image manager instance...");
        sharedInstance = [MLImageManager new];
    });
    return sharedInstance;
}

//this mehod should *only* be used in the mainapp due to memory requirements for large images
//isaCloud: colors of the isaCloud palette (isaCloudPink and isaCloudBlue asset colors); the framework cannot load them by name
+(UIImage*) defaultMucIconForChannel:(BOOL) isChannel
{
    CGFloat size = 256;
    UIColor* background = isChannel ?
        [UIColor colorWithRed:255.0/255.0 green:0.0/255.0 blue:111.0/255.0 alpha:1.0] :
        [UIColor colorWithRed:23.0/255.0 green:128.0/255.0 blue:173.0/255.0 alpha:1.0];
    UIImageSymbolConfiguration* config = [UIImageSymbolConfiguration configurationWithPointSize:size * 0.42 weight:UIImageSymbolWeightMedium];
    UIImage* symbol = [[UIImage systemImageNamed:isChannel ? @"number" : @"person.3.fill" withConfiguration:config] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext* context) {
        [background setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size, size)] fill];
        CGSize symbolSize = symbol.size;
        [symbol drawInRect:CGRectMake((size - symbolSize.width) / 2, (size - symbolSize.height) / 2, symbolSize.width, symbolSize.height)];
    }];
}

+(UIImage*) circularImage:(UIImage*) image
{
    return [[[UIGraphicsImageRenderer alloc] initWithSize:image.size] imageWithActions:^(UIGraphicsImageRendererContext* _Nonnull rendererContext) {
        UIBezierPath* clipPath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
        [clipPath addClip];
        
        //Flip coordinates before drawing image as UIKit and CoreGraphics have inverted coordinate system
        CGContextTranslateCTM(rendererContext.CGContext, 0, image.size.height);
        CGContextScaleCTM(rendererContext.CGContext, 1, -1);
        
        CGContextDrawImage(rendererContext.CGContext, CGRectMake(0, 0, image.size.width, image.size.height), image.CGImage);
    }];
}

+(UIImage*) image:(UIImage*) image withMucOverlay:(UIImage*) overlay
{
    UIGraphicsImageRendererFormat* format = [UIGraphicsImageRendererFormat new];
    format.opaque = NO;
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    format.scale = 1.0;
    CGRect drawRect = CGRectMake(0, 0, image.size.width, image.size.height);
    CGFloat overlaySize = (float)(image.size.width / 3);
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:drawRect.size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext* _Nonnull context __unused) {
        [image drawInRect:drawRect];
        CGRect overlayRect = CGRectMake(0,                  //renderer.format.bounds.size.width - overlaySize
                                        0,                  //renderer.format.bounds.size.height - overlaySize
                                        overlaySize,
                                        overlaySize);
        [overlay drawInRect:overlayRect];
    }];
}

-(id) init
{
    self = [super init];
    self.iconCache = [NSCache new];
    self.backgroundCache = [NSCache new];
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    self.documentsDirectory = [[HelperTools getContainerURLForPathComponents:@[]] path];
    
    NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"imagecache"];
    [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:nil];
    [HelperTools configureFileProtectionFor:writablePath];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMemoryPressureNotification) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    
    return self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) handleMemoryPressureNotification
{
    DDLogVerbose(@"Removing all objects in avatar cache due to memory pressure...");
    [self purgeCache];
}

#pragma mark cache

-(void) purgeCache
{
    [self.iconCache removeAllObjects];
    [self.backgroundCache removeAllObjects];
}

-(void) purgeCacheForContact:(NSString*) contact andAccount:(NSNumber*) accountID
{
    [self.iconCache removeObjectForKey:[NSString stringWithFormat:@"%@_%@", accountID, contact]];
    [self resetCachedBackgroundImageForContact:[MLContact createContactFromJid:contact andAccountID:accountID]];
}

-(void) cleanupHashes
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSArray<MLContact*>* contactList = [[DataLayer sharedInstance] contactList];
    
    for(MLContact* contact in contactList)
    {
        NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
        writablePath = [writablePath stringByAppendingPathComponent:contact.accountID.stringValue];
        writablePath = [writablePath stringByAppendingPathComponent:[self fileNameforContact:contact]];
        NSString* hash = [[DataLayer sharedInstance] getAvatarHashForContact:contact.contactJid andAccount:contact.accountID];
        BOOL hasHash = ![@"" isEqualToString:hash];
        
        if(hasHash && ![fileManager isReadableFileAtPath:writablePath])
        {
            DDLogDebug(@"Deleting orphan hash '%@' of contact: %@", hash, contact);
            //delete avatar hash from db if the file containing our image data vanished
            [[DataLayer sharedInstance] setAvatarHash:@"" forContact:contact.contactJid andAccount:contact.accountID];
        }
        
        if(!hasHash && [fileManager isReadableFileAtPath:writablePath])
        {
            DDLogDebug(@"Deleting orphan avatar file '%@' of contact: %@", writablePath, contact);
            NSError* error;
            [fileManager removeItemAtPath:writablePath error:&error];
            if(error)
                DDLogError(@"Error deleting orphan avatar file: %@", error);
        }
    }
}

-(void) removeAllIcons
{
    NSError* error;
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
    [fileManager removeItemAtPath:writablePath error:&error];
    if(error)
        DDLogError(@"Got error while trying to delete all avatar files: %@", error);
}

#pragma mark chat bubbles

-(UIImage*) inboundImage
{
    if(_inboundImage)
        return _inboundImage;
    _inboundImage = [[UIImage imageNamed:ACImageNameIncoming] resizableImageWithCapInsets:UIEdgeInsetsMake(6, 6, 6, 6)];
    return _inboundImage;
    
}

-(UIImage*) outboundImage
{
    if (_outboundImage)
        return _outboundImage;
    _outboundImage = [[UIImage imageNamed:ACImageNameOutgoing] resizableImageWithCapInsets:UIEdgeInsetsMake(6, 6, 6, 6)];
    return _outboundImage;
}

#pragma mark user icons

-(UIImage*) generateDummyIconForContact:(MLContact*) contact
{
    NSString* name;
    if(contact.isSelf)
        name = [MLContact ownDisplayNameForAccount:contact.account];
    else
        name = [contact contactDisplayName];
    return [self generateDummyIconWithName:name andColorInput:contact.contactJid];
}

//isaCloud: one letter ("isa" -> "I") or two letters for names with several words ("Isadora Ribeiro" -> "IR")
+(NSString*) initialsForName:(NSString*) name
{
    NSMutableArray<NSString*>* words = [NSMutableArray new];
    for(NSString* word in [name componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]])
        if(word.length > 0)
            [words addObject:word];
    if(words.count == 0)
        return @"?";
    //use composed character sequences to not split emojis or accented letters
    NSString* (^firstCharacter)(NSString*) = ^NSString*(NSString* word) {
        return [[word substringWithRange:[word rangeOfComposedCharacterSequenceAtIndex:0]] uppercaseString];
    };
    if(words.count == 1)
        return firstCharacter(words.firstObject);
    return [NSString stringWithFormat:@"%@%@", firstCharacter(words.firstObject), firstCharacter(words.lastObject)];
}

//isaCloud: circular avatar with the name's initials on a XEP-0392 color derived from colorInput (jid or occupant jid)
-(UIImage*) generateDummyIconWithName:(NSString*) name andColorInput:(NSString*) colorInput
{
    NSString* contactLetters = [MLImageManager initialsForName:name];
    UIColor* background = [HelperTools generateColorFromJid:colorInput];
    UIColor* foreground = [UIColor blackColor];
    if(![background isLightColor])
        foreground = [UIColor whiteColor];
    
    CGRect drawRect = CGRectMake(0, 0, 200, 200);
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:drawRect.size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        //make sure our image is circular
        [[UIBezierPath bezierPathWithOvalInRect:drawRect] addClip];
        
        //fill the background of our image
        [background setFill];
        [context fillRect:renderer.format.bounds];
        
        //draw letters in the middle of our image (smaller font for two letters)
        NSMutableParagraphStyle* paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
        paragraphStyle.alignment = NSTextAlignmentCenter;
        double fontDivisor = [contactLetters length] > 1 ? 2.4 : 1.666;
        NSDictionary* attributes = @{
            NSFontAttributeName: [[UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle] fontWithSize:(unsigned int)(drawRect.size.height / fontDivisor)],
            NSForegroundColorAttributeName: foreground,
            NSParagraphStyleAttributeName: paragraphStyle
        };
        CGSize textSize = [contactLetters sizeWithAttributes:attributes];
        CGRect textRect = CGRectMake(floorf((float)(renderer.format.bounds.size.width - textSize.width) / 2),
                                    floorf((float)(renderer.format.bounds.size.height - textSize.height) / 2),
                                    textSize.width,
                                    textSize.height);
        [contactLetters drawInRect:textRect withAttributes:attributes];
    }];
}

-(NSString*) fileNameforContact:(MLContact*) contact
{
    return [NSString stringWithFormat:@"%@_%@.png", contact.accountID.stringValue, [contact.contactJid lowercaseString]];;
}

-(NSString*) fileNameforThumbnailOfMessage:(MLMessage*) message
{
    return [NSString stringWithFormat:@"%@.png", message.messageDBId.stringValue];
}

-(NSURL*) setThumbnailOfMessage:(MLMessage*) message withData:(NSData* _Nullable) data
{
    //documents directory/thumbnails/accountID/contact

    NSString* filename = [self fileNameforThumbnailOfMessage:message];

    NSFileManager* fileManager = [NSFileManager defaultManager];

    NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"thumbnails"];
    writablePath = [writablePath stringByAppendingPathComponent:message.accountID.stringValue];
    writablePath = [writablePath stringByAppendingPathComponent:message.buddyName];
    NSError* error;
    [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:&error];
    [HelperTools configureFileProtectionFor:writablePath];
    writablePath = [writablePath stringByAppendingPathComponent:filename];

    if([fileManager fileExistsAtPath:writablePath])
        [fileManager removeItemAtPath:writablePath error:nil];

    if(data)
    {
        if([data writeToFile:writablePath atomically:NO])
        {
            [HelperTools configureFileProtectionFor:writablePath];
            DDLogVerbose(@"wrote image to file: %@", writablePath);
            return [NSURL fileURLWithPath:writablePath];
        }
        else
            DDLogError(@"failed to write image to file: %@", writablePath);
    }
    return (NSURL*)nil;
}

-(void) setIconForContact:(MLContact*) contact WithData:(NSData* _Nullable) data
{
    //documents directory/buddyicons/account no/contact
    
    NSString* filename = [self fileNameforContact:contact];
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    NSString *writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
    writablePath = [writablePath stringByAppendingPathComponent:contact.accountID.stringValue];
    NSError* error;
    [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:&error];
    [HelperTools configureFileProtectionFor:writablePath];
    writablePath = [writablePath stringByAppendingPathComponent:filename];
    
    if([fileManager fileExistsAtPath:writablePath])
        [fileManager removeItemAtPath:writablePath error:nil];

    if(data)
    {
        if([data writeToFile:writablePath atomically:NO])
        {
            [HelperTools configureFileProtectionFor:writablePath];
            DDLogVerbose(@"wrote image to file: %@", writablePath);
        }
        else
            DDLogError(@"failed to write image to file: %@", writablePath);
    }
    
    //remove from cache if its there
    [self.iconCache removeObjectForKey:[NSString stringWithFormat:@"%@_%@", contact.accountID, contact]];
    
}

-(BOOL) hasIconForContact:(MLContact*) contact
{
    NSString* filename = [self fileNameforContact:contact];
    
    NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
    writablePath = [writablePath stringByAppendingPathComponent:contact.accountID.stringValue];
    writablePath = [writablePath stringByAppendingPathComponent:filename];
    
    DDLogVerbose(@"Checking avatar image at: %@", writablePath);
    return [UIImage imageWithContentsOfFile:writablePath] != nil;
}

-(NSURL*) getThumbnailURLOfMessage:(MLMessage*) message
{
    NSString* path = [self.documentsDirectory stringByAppendingPathComponent:@"thumbnails"];
    path = [path stringByAppendingPathComponent:message.accountID.stringValue];
    path = [path stringByAppendingPathComponent:message.buddyName];
    NSString* filename = [self fileNameforThumbnailOfMessage:message];
    path = [path stringByAppendingPathComponent:filename];
    if([[NSFileManager defaultManager] fileExistsAtPath:path])
        return [NSURL fileURLWithPath:path];
    else
        return nil;
}

-(UIImage*) getIconForContact:(MLContact*) contact
{
    return [self getIconForContact:contact withCompletion:nil];
}

-(UIImage*) getIconForContact:(MLContact*) contact withCompletion:(void (^)(UIImage *))completion
{
    NSString* filename = [self fileNameforContact:contact];
    
    __block UIImage* toreturn = nil;
    //get filname from DB
    NSString* cacheKey = [NSString stringWithFormat:@"%@_%@", contact.accountID, contact.contactJid];
    
    //check cache
    toreturn = [self.iconCache objectForKey:cacheKey];
    if(!toreturn)
    {
        NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
        writablePath = [writablePath stringByAppendingPathComponent:contact.accountID.stringValue];
        writablePath = [writablePath stringByAppendingPathComponent:filename];
        
        DDLogVerbose(@"Loading avatar image at: %@", writablePath);
        UIImage* savedImage = [UIImage imageWithContentsOfFile:writablePath];
        if(savedImage)
            toreturn = savedImage;
        DDLogVerbose(@"Loaded image: %@", toreturn);
        
        if(toreturn == nil)             //return default avatar
        {
            DDLogVerbose(@"Using/generating dummy icon for contact: %@", contact);
            if(contact.isMuc)
            {
                if([kMucTypeChannel isEqualToString:contact.mucType])
                    toreturn = [MLImageManager defaultMucIconForChannel:YES];
                else
                    toreturn = [MLImageManager defaultMucIconForChannel:NO];
            }
            else
                toreturn = [self generateDummyIconForContact:contact];
        }
        else if(contact.isMuc)        //add group indicator overlay for non-default muc avatar
        {
            UIImage* overlay = nil;
            if([kMucTypeChannel isEqualToString:contact.mucType])
                overlay = [MLImageManager defaultMucIconForChannel:YES];
            else
                overlay = [MLImageManager defaultMucIconForChannel:NO];
            if(overlay)
                toreturn = [MLImageManager image:toreturn withMucOverlay:overlay];
        }
        
        //uiimage is cached if avaialable, but only if not in appex due to memory limits therein
        if(toreturn && ![HelperTools isAppExtension])
            [self.iconCache setObject:toreturn forKey:cacheKey];
        
        if(completion)
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(toreturn);
            });
    }
    else if(completion)
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(toreturn);
        });
    return toreturn;
}


-(void) saveBackgroundImageData:(NSData* _Nullable) data forContact:(MLContact* _Nullable) contact
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* writablePath;
    if(contact != nil)
    {
        NSString* filename = [self fileNameforContact:contact];
        writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"backgrounds"];
        
        [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:nil];
        [HelperTools configureFileProtectionFor:writablePath];
        
        writablePath = [writablePath stringByAppendingPathComponent:filename];
        if([fileManager fileExistsAtPath:writablePath])
            [fileManager removeItemAtPath:writablePath error:nil];
    }
    else
    {
        writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"background.jpg"];
        if([fileManager fileExistsAtPath:writablePath])
            [fileManager removeItemAtPath:writablePath error:nil];
    }
    [self resetCachedBackgroundImageForContact:contact];
    
    //file was deleted above, just don't create it again
    if(data != nil)
    {
        DDLogVerbose(@"Writing background image data %@ for %@ to '%@'...", data, contact, writablePath);
        [data writeToFile:writablePath atomically:YES];
        [HelperTools configureFileProtectionFor:writablePath];
    }
    
    //don't queue this notification because it should be handled immediately
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalBackgroundChanged object:contact];
}

-(UIImage* _Nullable) getBackgroundFor:(MLContact* _Nullable) contact
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* filename = @"background.jpg";
    if(contact != nil)
        filename = [self fileNameforContact:contact];
    UIImage* img = [self.backgroundCache objectForKey:filename];
    if(img != nil)
        return img;
    
    NSString* writablePath;
    if(contact != nil)
    {
        writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"backgrounds"];
        writablePath = [writablePath stringByAppendingPathComponent:filename];
        if(![fileManager fileExistsAtPath:writablePath])
            return nil;
    }
    else
    {
        writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"background.jpg"];
        if(![fileManager fileExistsAtPath:writablePath])
            return nil;
    }
    DDLogVerbose(@"Loading background image for %@ from '%@'...", contact, writablePath);
    img = [UIImage imageWithContentsOfFile:writablePath];
    DDLogVerbose(@"Got image: %@", img);
    [self.backgroundCache setObject:img forKey:filename];
    return img;
}

-(void) resetCachedBackgroundImageForContact:(MLContact* _Nullable) contact
{
    NSString* filename = @"background.jpg";
    if(contact != nil)
        filename = [self fileNameforContact:contact];
    [self.backgroundCache removeObjectForKey:filename];
}

@end
