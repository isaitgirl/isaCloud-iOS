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
@class MLXMLNode;
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

//isaCloud: nick of this account in ONE group or channel (XEP-0045 7.6), independent of the display name of the account.
//The result goes to the ui handler of the room (see addUIHandler:forMuc:): success, or an error with the reason of the service.
//Joined room: the nick is saved only after the service confirmed it. Not joined: saved and used by the next join.
-(void) changeNickOfMuc:(NSString*) room to:(NSString*) nick;
//isaCloud: the nick of a room is part of its bookmark (XEP-0402 <nick/>): without it the next bookmarks fetch after a reconnect would bring the old nick back.
//Only the item of this ONE room is fetched and published again (never the whole list) and the other bookmark updates carry the local nick meanwhile.
-(void) updateBookmarks;
//isaCloud: another device (or client) changed the nick of this room in the bookmark: follow it, WITHOUT the "joining" state of a normal join.
//Joined room: same nick change as changeNickOfMuc:to:, but silent (no ui handler, no bookmark publish: the bookmark already has it).
-(void) adoptNick:(NSString*) nick forMuc:(NSString*) room;
-(void) publishNickBookmarkForMuc:(NSString*) room;
-(BOOL) isNickBookmarkPendingForMuc:(NSString*) room;
-(void) finishNickBookmarkForMuc:(NSString*) room;
//sets <nick/> of a bookmark item to the nick we have in the database for this room
-(void) setOwnNickOfMuc:(NSString*) room inBookmarkItem:(MLXMLNode*) item;
//isaCloud: trimmed nick if it can be used in a room (not empty, no '/' or '@', no control characters, at most 100 characters), nil otherwise
+(NSString* _Nullable) validatedNick:(NSString*) nick;

//isaCloud: directed presence to all joined rooms (e.g. to publish a new avatar hash)
-(void) sendPresenceToJoinedMucs;
-(void) pingAllMucs;
-(void) ping:(NSString*) roomJid;
-(BOOL) checkIfStillBookmarked:(NSString*) room;
-(NSSet*) getRoomFeaturesForMuc:(NSString*) room;

@end

NS_ASSUME_NONNULL_END
