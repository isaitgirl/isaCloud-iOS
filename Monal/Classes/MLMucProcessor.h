//
//  MLMucProcessor.h
//  monalxmpp
//
//  Created by Thilo Molitor on 29.12.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <monalxmpp/MLConstants.h>

NS_ASSUME_NONNULL_BEGIN

@class XMPPPresence;
@class XMPPMessage;
@class xmpp;

@interface MLMucProcessor : NSObject

-(void) addUIHandler:(monal_id_block_t) handler forMuc:(NSString*) room;
-(void) removeUIHandlerForMuc:(NSString*) room;

-(void) processPresence:(XMPPPresence*) presenceNode;
-(BOOL) processMessage:(XMPPMessage*) messageNode;

-(void) join:(NSString*) room;
-(void) leave:(NSString*) room withBookmarksUpdate:(BOOL) updateBookmarks keepBuddylistEntry:(BOOL) keepBuddylistEntry;

//muc management methods
-(NSString* _Nullable) generateMucJid;
//isaCloud: public channels of the server's MUC service (XEP-0030 disco#items), completion gets NSArray of @{@"jid", @"name"} or NSNull on error
-(void) queryPublicChannelsWithCompletion:(monal_id_block_t) completion;
//isaCloud: occupant count of a room (muc#roominfo_occupants from disco#info), completion gets NSNumber or NSNull when the server does not publish it
-(void) queryMemberCountOfRoom:(NSString*) room completion:(monal_id_block_t) completion;
//isaCloud: avatar of a room (vcard-temp, not stored), completion gets NSData or NSNull
-(void) queryAvatarOfRoom:(NSString*) room completion:(monal_id_block_t) completion;
-(NSString* _Nullable) createGroup:(NSString*) room;
-(void) destroyRoom:(NSString*) room;
-(void) changeNameOfMuc:(NSString*) room to:(NSString*) name;
-(void) changeSubjectOfMuc:(NSString*) room to:(NSString*) subject;
-(void) requestVoiceInMuc:(NSString*) roomJid;
-(AnyPromise*) publishAvatar:(UIImage* _Nullable) image forMuc:(NSString*) room;
-(AnyPromise*) setAffiliation:(NSString*) affiliation ofUser:(NSString*) jid inMuc:(NSString*) roomJid;
-(void) inviteUser:(NSString*) jid inMuc:(NSString*) roomJid;

//isaCloud: directed presence to all joined rooms (e.g. to publish a new avatar hash)
-(void) sendPresenceToJoinedMucs;
-(void) pingAllMucs;
-(void) ping:(NSString*) roomJid;
-(BOOL) checkIfStillBookmarked:(NSString*) room;
-(NSSet*) getRoomFeaturesForMuc:(NSString*) room;

@end

NS_ASSUME_NONNULL_END
