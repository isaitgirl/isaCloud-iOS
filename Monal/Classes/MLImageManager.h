//
//  MLImageManager.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/16/13.
//
//

#import <Foundation/Foundation.h>

@import UIKit;
@class MLContact;
@class MLMessage;

@interface MLImageManager : NSObject

/**
 chatview inbound background image
 */
@property (nonatomic, strong) UIImage* _Nullable inboundImage;
/**
 chatview outbound background image
 */
@property (nonatomic, strong) UIImage* _Nullable outboundImage;


+(MLImageManager* _Nonnull) sharedInstance;
-(void) cleanupHashes;
-(void) removeAllIcons;

/**
 Takes the string from the xmpp icon vcard info and stores it in an appropropriate place. 
 */
-(void) setIconForContact:(MLContact* _Nonnull) contact WithData:(NSData* _Nullable) data ;

/**
 retrieves a uiimage for the icon. returns noicon.png if nothing is found. never returns nil.
 */
-(BOOL) hasIconForContact:(MLContact* _Nonnull) contact;
-(UIImage* _Nullable) getIconForContact:(MLContact* _Nonnull) contact withCompletion:(void (^_Nullable)(UIImage *_Nullable))completion;
-(UIImage* _Nullable) getIconForContact:(MLContact* _Nonnull) contact;
+(UIImage* _Nonnull) circularImage:(UIImage* _Nonnull) image;
//isaCloud: default avatar of a group (blue, people symbol) or a channel (pink, # symbol)
+(UIImage* _Nonnull) defaultMucIconForChannel:(BOOL) isChannel;
//isaCloud: initials avatar with a XEP-0392 color
+(NSString* _Nonnull) initialsForName:(NSString* _Nullable) name;
-(UIImage* _Nonnull) generateDummyIconWithName:(NSString* _Nullable) name andColorInput:(NSString* _Nonnull) colorInput;

//isaCloud: avatars of people we have no PEP avatar from (members of groups, participants of channels), stored by their hash:
//the same image is stored once, even if the person is in many rooms. "owner" is a bare jid or room|occupant-id, see DataLayer.h
-(BOOL) hasRemoteAvatarForHash:(NSString* _Nonnull) hash;
-(void) saveRemoteAvatarData:(NSData* _Nonnull) data forHash:(NSString* _Nonnull) hash;
-(UIImage* _Nullable) remoteAvatarForOwner:(NSString* _Nonnull) owner accountID:(NSNumber* _Nonnull) accountID;

-(NSURL* _Nullable) getThumbnailURLOfMessage:(MLMessage* _Nonnull) message;
-(NSURL* _Nullable) setThumbnailOfMessage:(MLMessage* _Nonnull) message withData:(NSData* _Nullable) data;

-(void) saveBackgroundImageData:(NSData* _Nullable) data forContact:(MLContact* _Nullable) contact;
-(UIImage* _Nullable) getBackgroundFor:(MLContact* _Nullable) contact;

/**
 Purge cache in the event of  a memory warning
 */
-(void) purgeCache;
-(void) purgeCacheForContact:(NSString* _Nonnull) contact andAccount:(NSNumber* _Nonnull) accountID;

@end
