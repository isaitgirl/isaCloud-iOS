//
//  MLMucProcessor.m
//  monalxmpp
//
//  Created by Thilo Molitor on 29.12.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <monalxmpp/MLConstants.h>
#import <monalxmpp/MLMucProcessor.h>
#import <monalxmpp/MLHandler.h>
#import <monalxmpp/xmpp.h>
#import <monalxmpp/DataLayer.h>
#import <monalxmpp/XMPPDataForm.h>
#import "XMPPIQ.h"
#import "XMPPMessage.h"
#import <monalxmpp/XMPPPresence.h>
#import <monalxmpp/MLNotificationQueue.h>
#import <monalxmpp/MLPubSub.h>
#import <monalxmpp/MLPubSubProcessor.h>
#import <monalxmpp/MLOMEMO.h>
#import <monalxmpp/MLImageManager.h>

//monal version 7.x state counter: 010
#define CURRENT_MUC_STATE_VERSION @7010

@interface MLMucProcessor()
{
    __weak xmpp* _account;
    BOOL _smacksResumption;
    BOOL _shouldFetchBookmarks;
    //persistent state
    NSObject* _stateLockObject;
    NSMutableDictionary* _roomFeatures;
    NSMutableDictionary* _creating;
    NSMutableDictionary* _joining;
    NSMutableSet* _joined;
    NSMutableSet* _destroying;
    NSMutableSet* _firstJoin;
    NSMutableDictionary* _changingName;
    NSMutableSet* _nickBookmarkPending;     //isaCloud: rooms whose new nick is not in the remote bookmark yet (memory only)
    NSMutableDictionary* _changingNick;     //isaCloud: room --> @{nick, oldNick, token} of a nick change waiting for the answer of the service (memory only, never saved)
    NSDate* _lastPing;
    NSMutableSet* _noUpdateBookmarks;
    //these won't be persisted because it is only for the ui
    NSMutableDictionary* _uiHandler;
}
@end

@implementation MLMucProcessor

static NSDictionary* _mandatoryGroupConfigOptions;
static NSDictionary* _optionalGroupConfigOptions;
//isaCloud: the MUC component of each server we run (account domain -> component); other servers keep the first one advertised
static NSDictionary* _ownMucComponents;
//isaCloud: the guide channel of the server; it goes to the recent conversations every time it is joined
static NSString* const kIsaCloudGuideRoom = @"guiaxmpp@conference.isacloud.cc";

+(void) initialize
{
    _ownMucComponents = @{
        @"isacloud.im": @"conference.isacloud.cc",
        @"xmpp.social.br": @"canais.xmpp.social.br",
        @"voz.social.br": @"canais.voz.social.br",
    };
    //isaCloud: persistentroom is optional, some servers do not offer it in the config form; we check persistence afterwards
    _mandatoryGroupConfigOptions = @{
        @"muc#roomconfig_membersonly": @"1",
        @"muc#roomconfig_whois": @"anyone",
        //TODO: mark mam as mandatory
    };
    _optionalGroupConfigOptions = @{
        @"muc#roomconfig_persistentroom": @"1",
        @"muc#roomconfig_enablelogging": @"0",
        @"muc#roomconfig_changesubject": @"0",
        @"muc#roomconfig_allowinvites": @"0",
        @"muc#roomconfig_getmemberlist": kMucRoleParticipant,
        @"muc#roomconfig_publicroom": @"0",
        @"muc#roomconfig_moderatedroom": @"0",
        @"muc#maxhistoryfetch": @"0",               //should use mam
    };
    
}

-(id) initWithAccount:(xmpp*) account
{
    self = [super init];
    _account = account;
    _stateLockObject = [NSObject new];
    _roomFeatures = [NSMutableDictionary new];
    _creating = [NSMutableDictionary new];
    _joining = [NSMutableDictionary new];
    _joined = [NSMutableSet new];
    _destroying = [NSMutableSet new];
    _firstJoin = [NSMutableSet new];
    _changingName = [NSMutableDictionary new];
    _changingNick = [NSMutableDictionary new];
    _nickBookmarkPending = [NSMutableSet new];
    _uiHandler = [NSMutableDictionary new];
    _lastPing = [NSDate date];
    _noUpdateBookmarks = [NSMutableSet new];
    _shouldFetchBookmarks = NO;
    _smacksResumption = YES;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleHasLoggedIn:) name:kMLIsLoggedInNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleResourceBound:) name:kMLResourceBoundNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleSessionInit:) name:kMLSessionInitNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleCatchupDone:) name:kMonalFinishedCatchup object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleSentMessage:) name:kMonalSentMessageNotice object:nil];
    return self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) setInternalState:(NSDictionary*) state
{
    //DDLogVerbose(@"Setting MUC state to: %@", state);
    
    //ignore state having wrong version code
    if(!state[@"version"] || ![state[@"version"] isEqual:CURRENT_MUC_STATE_VERSION])
    {
        DDLogDebug(@"Ignoring MUC state having wrong version: %@ != %@", state[@"version"], CURRENT_MUC_STATE_VERSION);
        return;
    }
    
    //extract state
    @synchronized(_stateLockObject) {
        _roomFeatures = [state[@"roomFeatures"] mutableCopy];
        _creating = [state[@"creating"] mutableCopy];
        _joining = [state[@"joining"] mutableCopy];
        _joined = [state[@"joined"] mutableCopy];
        _destroying = [state[@"destroying"] mutableCopy];
        _firstJoin = [state[@"firstJoin"] mutableCopy];
        _changingName = [state[@"changingName"] mutableCopy];
        _lastPing = state[@"lastPing"];
        _noUpdateBookmarks = [state[@"noUpdateBookmarks"] mutableCopy];
    }
}

-(NSDictionary*) getInternalState
{
    @synchronized(_stateLockObject) {
        NSDictionary* state = @{
            @"version": CURRENT_MUC_STATE_VERSION,
            @"roomFeatures": [_roomFeatures copy],
            @"creating": [_creating copy],
            @"joining": [_joining copy],
            @"joined": [_joined copy],
            @"destroying": [_destroying copy],
            @"firstJoin": [_firstJoin copy],
            @"changingName": [_changingName copy],
            @"lastPing": _lastPing,
            @"noUpdateBookmarks": [_noUpdateBookmarks copy],
        };
        //DDLogVerbose(@"Returning MUC state: %@", state);
        return state;
    }
}

-(void) handleHasLoggedIn:(NSNotification*) notification
{
    //this event will be called as soon as we are successfully authenticated, but BEFORE handleResourceBound: will be called
    //NOTE: handleResourceBound: won't be called for smacks resumptions at all
    if(_account == ((xmpp*)notification.object))
    {
        _smacksResumption = YES;        //will be reset to NO, in handleResourceBound
        _shouldFetchBookmarks = NO;     //will be reset to YES in handleResourceBound
    }
}

-(void) handleResourceBound:(NSNotification*) notification
{
    //this event will be called as soon as we are bound, but BEFORE mam catchup happens
    //NOTE: this event won't be called for smacks resumes!
    if(_account == ((xmpp*)notification.object))
    {
        //reset our state
        @synchronized(_stateLockObject) {
            _joined = [NSMutableSet new];
            _roomFeatures = [NSMutableDictionary new];
            _destroying = [NSMutableSet new];
            _changingName = [NSMutableDictionary new];
            _changingNick = [NSMutableDictionary new];
            _nickBookmarkPending = [NSMutableSet new];
            
            //make sure all idle timers get invalidated properly
            NSDictionary* joiningCopy = [_joining copy];
            for(NSString* room in joiningCopy)
                 [self removeRoomFromJoining:room];
            NSDictionary* creatingCopy = [_creating copy];
            for(NSString* room in creatingCopy)
                 [self removeRoomFromCreating:room];
            
            //don't clear _firstJoin and _noUpdateBookmarks to make sure half-joined mucs are still added to muc bookmarks
            
            //load all bookmarks 2 items as soon as our catchup is done (+notify only provides one/the last item)
            _shouldFetchBookmarks = YES;
            
            //mark this as non-smacks reconnect
            _smacksResumption = NO;
        }
    }
}

-(void) handleSessionInit:(NSNotification*) notification
{
    //this event will be called as soon as we are bound AND smacks is enabled/resumed
    //but: we only want to join rooms if this was a non-smacks reconnect (we only want to periodically ping mucs when smacks resuming)
    if(_account == ((xmpp*)notification.object) && !_smacksResumption)
    {
        //join MUCs from (current) muc_favorites db, the pending bookmarks fetch will join the remaining currently unknown mucs
        for(NSString* room in [[DataLayer sharedInstance] listMucsForAccount:_account.accountID])
            [self join:room];
    }
}

-(void) handleCatchupDone:(NSNotification*) notification
{
    //this event will be called as soon as mam OR smacks catchup on our account is done, it does not wait for muc mam catchups!
    if(_account == ((xmpp*)notification.object))
    {
        //fake incoming bookmarks push by pulling all bookmarks2 items
        //don't use [self updateBookmarks] to not update anything (e.g. readd a bookmark removed by another client)
        if(_shouldFetchBookmarks)
            [_account.pubsub fetchNode:@"urn:xmpp:bookmarks:1" from:_account.connectionProperties.identity.jid withItemsList:nil andHandler:$newHandler(MLPubSubProcessor, bookmarks2Handler, $ID(type, @"publish"))];
    }
}

-(void) handleSentMessage:(NSNotification*) notification
{
    XMPPMessage* msg = notification.userInfo[@"message"];
    NSString* callUiHandlerFor = nil;
    
    //check if this is a direct invite
    if([msg check:@"/{jabber:client}message<type=normal>/{jabber:x:conference}x@jid"])
        callUiHandlerFor = [msg findFirst:@"/{jabber:client}message<type=normal>/{jabber:x:conference}x@jid"];
    
    //check for muc subject change
    if([msg check:@"/{jabber:client}message<type=groupchat>/subject"])
        callUiHandlerFor = msg.toUser;
    
    if(callUiHandlerFor != nil)
        [self callSuccessUIHandlerForMuc:callUiHandlerFor];
}

-(BOOL) isCreating:(NSString*) room
{
    @synchronized(_stateLockObject) {
        return _creating[room] != nil;
    }
}

-(BOOL) isJoining:(NSString*) room
{
    @synchronized(_stateLockObject) {
        return _joining[room] != nil;
    }
}

-(BOOL) isJoined:(NSString*) room
{
    @synchronized(_stateLockObject) {
        return [_joined containsObject:room];
    }
}

-(BOOL) isDestroying:(NSString*) room
{
    @synchronized(_stateLockObject) {
        return [_destroying containsObject:room];
    }
}

-(BOOL) incrementNameChange:(NSString*) room
{
    @synchronized(_stateLockObject) {
        if(!_changingName[room])
        {
            _changingName[room] = @1;
            return YES;
        }
        _changingName[room] = @(((NSNumber*)_changingName[room]).integerValue + 1);
        return NO;
    }
}

-(BOOL) decrementNameChange:(NSString*) room
{
    @synchronized(_stateLockObject) {
        if(_changingName[room] == nil)
            return YES;
        NSInteger oldValue = ((NSNumber*)_changingName[room]).integerValue;
        _changingName[room] = @(max(0, oldValue - 1));
        //only return YES if there was no running name change (and NO if at least one was running)
        if(oldValue == 0)
            return YES;
        return NO;
    }
}

-(void) addUIHandler:(monal_id_block_t) handler forMuc:(NSString*) room
{
    //this will replace the old handler
    @synchronized(_stateLockObject) {
        DDLogVerbose(@"Adding ui handler for muc: %@", room);
        _uiHandler[room] = handler;
    }
}

-(void) removeUIHandlerForMuc:(NSString*) room
{
    @synchronized(_stateLockObject) {
        [_uiHandler removeObjectForKey:room];
    }
}

-(monal_id_block_t) getUIHandlerForMuc:(NSString*) room
{
    @synchronized(_stateLockObject) {
        return _uiHandler[room];
    }
}

-(void) processPresence:(XMPPPresence*) presenceNode
{
    //isaCloud: hats of the occupant (XEP-0317); a presence without hats (e.g. when leaving) removes them
    if(presenceNode.fromResource)
    {
        NSMutableArray<NSDictionary<NSString*, NSString*>*>* hats = [NSMutableArray new];
        for(MLXMLNode* hat in [presenceNode find:@"{urn:xmpp:hats:0}hats/hat"])
        {
            NSString* uri = hat.attributes[@"uri"];
            NSString* title = hat.attributes[@"title"];
            [hats addObject:@{@"uri": uri != nil ? uri : @"", @"title": title != nil ? title : @""}];
        }
        [[DataLayer sharedInstance] setMucHats:hats forRoom:presenceNode.fromUser nick:presenceNode.fromResource forAccountID:_account.accountID];
    }

    //isaCloud: answers to a nick change we asked for (an error presence MUST be handled here: below it would delete the room from favorites and bookmarks)
    if([self handleNickChangePresence:presenceNode])
        return;

    //check for nickname conflict while joining and retry with underscore added to the end
    if([self isJoining:presenceNode.fromUser] && [presenceNode findFirst:@"/<type=error>/error/{urn:ietf:params:xml:ns:xmpp-stanzas}conflict"])
    {
        //load old nickname from db, add underscore and write it back to db so that it can be used by our next join
        NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:presenceNode.fromUser forAccount:_account.accountID];
        nick = [NSString stringWithFormat:@"%@_", nick];
        [[DataLayer sharedInstance] initMuc:presenceNode.fromUser forAccountID:_account.accountID andMucNick:nick];
        
        //try to join again
        DDLogInfo(@"Retrying muc join of %@ with new nick (appended underscore): %@", presenceNode.fromUser, nick);
        [self removeRoomFromJoining:presenceNode.fromUser];
        [self sendJoinPresenceFor:presenceNode.fromUser];
        return;
    }
    
    //check for all other errors (these can happen if the muc is discoverable but joining somehow fails nonetheless like with biboumi)
    if([presenceNode check:@"/<type=error>/error<type=wait>"] && ([self isJoining:presenceNode.fromUser] || [self isJoined:presenceNode.fromUser]))
    {
        DDLogError(@"Got transient muc error presence of %@: %@", presenceNode.fromUser, [presenceNode findFirst:@"error"]);
        [self removeRoomFromJoining:presenceNode.fromUser];
        
        //do nothing: the error is only temporary (a s2s problem etc.), a muc ping will retry the join
        //this will keep the entry in local bookmarks table and remote bookmars
        //--> retry the join on mucPing or full login without smacks resume
        //this will also keep the buddy list entry
        //--> allow users to read the last messages before the muc got broken
        
        //only display an error banner, no notification (this is only temporary)
        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Temporary failure to enter Group/Channel: %@", @""), presenceNode.fromUser] forMuc:presenceNode.fromUser withNode:presenceNode andIsSevere:NO];
        return;
    }
    else if([presenceNode check:@"/<type=error>"] && ([self isJoining:presenceNode.fromUser] || [self isJoined:presenceNode.fromUser]))
    {
        DDLogError(@"Got permanent muc error presence of %@: %@", presenceNode.fromUser, [presenceNode findFirst:@"error"]);
        [self removeRoomFromJoining:presenceNode.fromUser];
        
        //delete muc from favorites table to be sure we don't try to rejoin it and update bookmarks afterwards (to make sure this muc isn't accidentally left in our boomkmarks)
        //make sure to update remote bookmarks, even if updateBookmarks == NO
        //keep buddy list entry to allow users to read the last messages before the muc got deleted/broken
        [self deleteMuc:presenceNode.fromUser withBookmarksUpdate:YES keepBuddylistEntry:YES];
        
        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Failed to enter Group/Channel %@", @""), presenceNode.fromUser] forMuc:presenceNode.fromUser withNode:presenceNode andIsSevere:YES];
        return;
    }
    
    //handle presences from muc bare jid
    if(presenceNode.fromResource == nil)
    {
        DDLogVerbose(@"Got muc presence from bare jid: %@", presenceNode.from);
        //check vcard hash
        NSString* avatarHash = [presenceNode findFirst:@"{vcard-temp:x:update}x/photo#"];
        NSString* currentHash = [[DataLayer sharedInstance] getAvatarHashForContact:presenceNode.fromUser andAccount:_account.accountID];
        DDLogVerbose(@"Checking if avatar hash in presence '%@' equals stored hash '%@'...", avatarHash, currentHash);
        if(avatarHash != nil && !(currentHash && [avatarHash isEqualToString:currentHash]))
        {
            DDLogInfo(@"Got new muc avatar hash '%@' for muc %@, fetching new image via vcard-temp...", avatarHash, presenceNode.fromUser);
            [self fetchAvatarForRoom:presenceNode.fromUser];
        }
        else if(avatarHash == nil && currentHash != nil && ![currentHash isEqualToString:@""])
        {
            [[MLImageManager sharedInstance] setIconForContact:[MLContact createContactFromJid:presenceNode.fromUser andAccountID:_account.accountID] WithData:nil];
            [[DataLayer sharedInstance] setAvatarHash:@"" forContact:presenceNode.fromUser andAccount:_account.accountID];
            //delete cache to make sure the image will be regenerated
            [[MLImageManager sharedInstance] purgeCacheForContact:presenceNode.fromUser andAccount:_account.accountID];
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
                @"contact": [MLContact createContactFromJid:presenceNode.fromUser andAccountID:_account.accountID]
            }];
            DDLogInfo(@"Avatar of muc '%@' deleted successfully", presenceNode.fromUser);
        }
        else
        {
            DDLogInfo(@"Avatar hash '%@' of muc %@ did not change, not updating avatar...", avatarHash, presenceNode.fromUser);
        }
    }
    //handle reflected presences
    else if([self isCreating:presenceNode.fromUser] || [self isJoining:presenceNode.fromUser] || [self isJoined:presenceNode.fromUser])
    {
        DDLogVerbose(@"Got muc presence from full jid: %@", presenceNode.from);
        
        //don't handle this error if we ourselves are destroying this room
        if(![self isDestroying:presenceNode.fromUser])
        {
            let mucContact = [MLContact createContactFromJid:presenceNode.fromUser andAccountID:_account.accountID];
            
            //extract info if present (use an empty dict if no info is present)
            NSMutableDictionary* item = [[presenceNode findFirst:@"{http://jabber.org/protocol/muc#user}x/item@@"] mutableCopy];
            if(!item)
                item = [NSMutableDictionary new];
            
            //update jid to be a bare jid and add muc nick to our dict
            if(item[@"jid"])
                item[@"jid"] = [HelperTools splitJid:item[@"jid"]][@"user"];
            item[@"nick"] = presenceNode.fromResource;
            if([_roomFeatures[presenceNode.fromUser] containsObject:@"urn:xmpp:occupant-id:0"])
                item[@"occupant_id"] = [presenceNode findFirst:@"{urn:xmpp:occupant-id:0}occupant-id@id"];
            
            //check for own role/affiliation change and send out a notification, if so
            NSString* oldAffiliation = nil;
            NSString* oldRole = nil;
            if([presenceNode check:@"{http://jabber.org/protocol/muc#user}x/status<code=110>"])
            {
                oldAffiliation= [[DataLayer sharedInstance] getOwnAffiliationInGroupOrChannel:mucContact];
                oldRole = [[DataLayer sharedInstance] getOwnRoleInGroupOrChannel:mucContact];
            }
            
            //handle participant updates
            if([presenceNode check:@"/<type=unavailable>"] || item[@"affiliation"] == nil)
            {
                DDLogVerbose(@"Removing participant from muc(%@): %@", presenceNode.fromUser, item);
                [[DataLayer sharedInstance] removeParticipant:item fromMuc:presenceNode.fromUser forAccountID:_account.accountID];
            }
            else
            {
                DDLogVerbose(@"Adding participant from muc(%@): %@", presenceNode.fromUser, item);
                [[DataLayer sharedInstance] addParticipant:item toMuc:presenceNode.fromUser forAccountID:_account.accountID];
            }
            
            //handle members updates (publishing the changes in members/participants is already handled by handleMembersListUpdate
            //--> only publish if we don't call handleMembersListUpdate
            if(item[@"jid"] != nil)
                [self handleMembersListUpdate:[presenceNode find:@"{http://jabber.org/protocol/muc#user}x/item@@"] forMuc:presenceNode.fromUser];
            else
            {
                DDLogDebug(@"Publishing participants list update...");
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalMucParticipantsAndMembersUpdated object:_account userInfo:@{
                    @"contact": mucContact,
                }];
            }
            
            if(oldAffiliation != nil || oldRole != nil)
            {
                DDLogDebug(@"Publishing own affiliation/role change...");
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalMucOwnAffiliationOrRoleChanged object:_account userInfo:@{
                    @"contact": mucContact,
                    @"oldAffiliation": nilWrapper(oldAffiliation),
                    @"oldRole": nilWrapper(oldRole),
                    @"newAffiliation": nilWrapper([[DataLayer sharedInstance] getOwnAffiliationInGroupOrChannel:mucContact]),
                    @"newRole": nilWrapper([[DataLayer sharedInstance] getOwnRoleInGroupOrChannel:mucContact]),
                }];
            }
        }
        else
            DDLogDebug(@"Ignoring unavailable presences of room being destroyed by us...");
        
        //handle muc status codes in reflected presences
        //this MUST be done after the above code to make sure the db correctly reflects our membership/participant status
        if([presenceNode check:@"/{jabber:client}presence/{http://jabber.org/protocol/muc#user}x/status@code"])
            [self handleStatusCodes:presenceNode];        
    }
    else
        DDLogWarn(@"Ignoring presence from room we are not joining and not joined to (probably the broken prosody smacks)!");
}

-(BOOL) processMessage:(XMPPMessage*) messageNode
{
    //only handle these if this is a known muc we are/want to be joined
    let contact = [MLContact createContactFromJid:messageNode.fromUser andAccountID:_account.accountID];
    if(contact.isMuc)
    {
        //handle member list updates of offline members (useful for members-only mucs)
        if([messageNode check:@"{http://jabber.org/protocol/muc#user}x/item"])
            [self handleMembersListUpdate:[messageNode find:@"{http://jabber.org/protocol/muc#user}x/item@@"] forMuc:messageNode.fromUser];
        
        //handle muc status codes
        [self handleStatusCodes:messageNode];
        
        //handle voice requests
        XMPPDataForm* voiceRequest = [[messageNode findFirst:@"\\{http://jabber.org/protocol/muc#request}form\\"] copy];
        if(voiceRequest != nil && [kMucRoleParticipant isEqualToString:voiceRequest[@"muc#role"]] && voiceRequest[@"muc#jid"] != nil)
        {
            let ownRole = [[DataLayer sharedInstance] getOwnRoleInGroupOrChannel:contact];
            if([kMucRoleModerator isEqualToString:ownRole])
            {
                [[DataLayer sharedInstance] addVoiceRequestBy:voiceRequest[@"muc#jid"] occupyingNick:voiceRequest[@"muc#roomnick"] inRoom:contact]; 
                DDLogDebug(@"Publishing new voice request...");
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalMucVoiceRequestsUpdated object:_account userInfo:@{
                    @"contact": contact,
                }];
                return YES;     //stop processing in MLMessageProcessor
            }
        }
    }
    
    //handle mediated invites
    if([messageNode check:@"{http://jabber.org/protocol/muc#user}x/invite"])
    {
        //ignore outgoing carbon copies or mam results
        if(![messageNode.toUser isEqualToString:_account.connectionProperties.identity.jid])
            return YES;     //stop processing in MLMessageProcessor and ignore this invite
        
        NSString* inviterJid = [HelperTools splitJid:[messageNode findFirst:@"{http://jabber.org/protocol/muc#user}x/invite@from"]][@"user"];
        if(inviterJid == nil)
        {
            DDLogError(@"mediated inivite does not include a MUC jid, ignoring invite");
            return YES;
        }
        MLContact* inviteFrom = [MLContact createContactFromJid:inviterJid andAccountID:_account.accountID];
        DDLogInfo(@"Got mediated muc invite from %@ for %@...", inviteFrom, messageNode.fromUser);
        if(/*![[HelperTools defaultsDB] boolForKey: @"allowNonRosterContacts"] &&*/ !inviteFrom.isSubscribedFrom)
        {
            DDLogWarn(@"Ignoring invite from %@, this jid isn't at least marked as susbscribedFrom in our roster...", inviteFrom);
            return YES;     //don't process this further
        }
        DDLogInfo(@"--> joining %@...", messageNode.fromUser);
        [self sendDiscoQueryFor:messageNode.fromUser withJoin:YES andBookmarksUpdate:YES];
        return YES;     //stop processing in MLMessageProcessor
    }
        
    //handle direct invites
    if([messageNode check:@"{jabber:x:conference}x@jid"] && [[messageNode findFirst:@"{jabber:x:conference}x@jid"] length] > 0)
    {
        //ignore outgoing carbon copies or mam results
        if(![messageNode.toUser isEqualToString:_account.connectionProperties.identity.jid])
            return YES;     //stop processing in MLMessageProcessor and ignore this invite
        
        MLContact* inviteFrom = [MLContact createContactFromJid:messageNode.fromUser andAccountID:_account.accountID];
        DDLogInfo(@"Got direct muc invite from %@ for %@ --> joining...", inviteFrom, [messageNode findFirst:@"{jabber:x:conference}x@jid"]);
        if(/*![[HelperTools defaultsDB] boolForKey: @"allowNonRosterContacts"] &&*/ !inviteFrom.isSubscribedFrom)
        {
            DDLogWarn(@"Ignoring invite from %@, this jid isn't at least marked as susbscribedFrom in our roster...", inviteFrom);
            return YES;     //don't process this further
        }
        DDLogInfo(@"--> joinging %@...", [messageNode findFirst:@"{jabber:x:conference}x@jid"]);
        [self sendDiscoQueryFor:[messageNode findFirst:@"{jabber:x:conference}x@jid"] withJoin:YES andBookmarksUpdate:YES];
        return YES;     //stop processing in MLMessageProcessor
    }
    
    //continue processing in MLMessageProcessor
    return NO;
}

-(void) handleMembersListUpdate:(NSArray<NSDictionary*>*) items forMuc:(NSString*) mucJid;
{
    //check if this is still a muc and ignore the members list update, if not
    if([[DataLayer sharedInstance] isBuddyMuc:mucJid forAccount:_account.accountID])
    {
        DDLogInfo(@"Handling members list update for %@: %@", mucJid, items);
        for(NSDictionary* entry in items)
        {
            NSMutableDictionary* item = [entry mutableCopy];
            if(!item || item[@"jid"] == nil)
            {
                DDLogDebug(@"Ignoring empty item/jid: %@", item);
                continue;       //ignore empty items or items without a jid
            }

            //update jid to be a bare jid
            item[@"jid"] = [HelperTools splitJid:item[@"jid"]][@"user"];
            
#ifndef DISABLE_OMEMO
            BOOL isTypeGroup = [[[DataLayer sharedInstance] getMucTypeOfRoom:mucJid andAccount:_account.accountID] isEqualToString:kMucTypeGroup];
#endif
            
            if(item[@"affiliation"] == nil || [kMucAffiliationNone isEqualToString:item[@"affiliation"]])
            {
                DDLogVerbose(@"Removing member '%@' from muc '%@'...", item[@"jid"], mucJid);
                [[DataLayer sharedInstance] removeMember:item fromMuc:mucJid forAccountID:_account.accountID];
#ifndef DISABLE_OMEMO
                if(isTypeGroup == YES)
                    [_account.omemo checkIfSessionIsStillNeeded:item[@"jid"] isMuc:NO];
#endif// DISABLE_OMEMO
            }
            else
            {
                DDLogVerbose(@"Adding member '%@' to muc '%@'...", item[@"jid"], mucJid);
                [[DataLayer sharedInstance] addMember:item toMuc:mucJid forAccountID:_account.accountID];
#ifndef DISABLE_OMEMO
                if(isTypeGroup == YES)
                    [_account.omemo subscribeAndFetchDevicelistIfNoSessionExistsForJid:item[@"jid"]];
#endif// DISABLE_OMEMO
            }
        }
        
        DDLogDebug(@"Publishing new memberslist...");
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalMucParticipantsAndMembersUpdated object:_account userInfo:@{
            @"contact": [MLContact createContactFromJid:mucJid andAccountID:_account.accountID]
        }];
    }
    else
        DDLogWarn(@"Ignoring handleMembersListUpdate for %@, MUC not in buddylist", mucJid);
}

-(void) configureMuc:(NSString*) roomJid withMandatoryOptions:(NSDictionary*) mandatoryOptions andOptionalOptions:(NSDictionary*) optionalOptions deletingMucOnError:(BOOL) deleteOnError andJoiningMucOnSuccess:(BOOL) joinOnSuccess
{
    DDLogInfo(@"Fetching room config form: %@", roomJid);
    XMPPIQ* configFetchNode = [[XMPPIQ alloc] initWithType:kiqGetType to:roomJid];
    [configFetchNode setGetRoomConfig];
    [_account sendIq:configFetchNode withHandler:$newHandlerWithInvalidation(self, handleRoomConfigForm, handleRoomConfigFormInvalidation, $ID(roomJid), $ID(mandatoryOptions), $ID(optionalOptions), $BOOL(deleteOnError), $BOOL(joinOnSuccess))];
}

$$instance_handler(handleRoomConfigFormInvalidation, account.mucProcessor, $$ID(xmpp*, account), $$ID(NSString*, roomJid), $$ID(NSDictionary*, mandatoryOptions), $$ID(NSDictionary*, optionalOptions), $$BOOL(deleteOnError))
    [self decrementNameChange:roomJid];
    if(deleteOnError)
    {
        DDLogError(@"Config form fetch failed, removing muc '%@' from _creating...", roomJid);
        [self removeRoomFromCreating:roomJid];
        [self deleteMuc:roomJid withBookmarksUpdate:NO keepBuddylistEntry:NO];
    }
    else
        DDLogError(@"Config form fetch failed for muc '%@'!", roomJid);
    [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Could not fetch room config form for '%@': please try again", @""), roomJid] forMuc:roomJid withNode:nil andIsSevere:YES];
$$

$$instance_handler(handleRoomConfigForm, account.mucProcessor, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, roomJid), $$ID(NSDictionary*, mandatoryOptions), $$ID(NSDictionary*, optionalOptions), $$BOOL(deleteOnError), $$BOOL(joinOnSuccess))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Failed to fetch room config form for '%@': %@", roomJid, [iqNode findFirst:@"error"]);
        [self decrementNameChange:roomJid];
        if(deleteOnError)
        {
            [self removeRoomFromCreating:roomJid];
            [self deleteMuc:roomJid withBookmarksUpdate:NO keepBuddylistEntry:NO];
        }
        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Failed to fetch room config form for '%@'", @""), roomJid] forMuc:roomJid withNode:iqNode andIsSevere:YES];
        return;
    }
    
    XMPPDataForm* dataForm = [[iqNode findFirst:@"{http://jabber.org/protocol/muc#owner}query/\\{http://jabber.org/protocol/muc#roomconfig}form\\"] copy];
    if(dataForm == nil)
    {
        DDLogError(@"Got empty room config form for '%@'!", roomJid);
        [self decrementNameChange:roomJid];
        if(deleteOnError)
        {
            [self removeRoomFromCreating:roomJid];
            [self deleteMuc:roomJid withBookmarksUpdate:NO keepBuddylistEntry:NO];
        }
        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Got empty room config form for '%@'", @""), roomJid] forMuc:roomJid withNode:nil andIsSevere:YES];
        return;
    }
    //these config options are mandatory and configure the room to be a group --> non anonymous, members only (and persistent)
    for(NSString* option in mandatoryOptions)
    {
        if([dataForm getField:option] == nil)
        {
            DDLogError(@"Could not configure room '%@' to be a groupchat: config option '%@' not available! Form fields: %@", roomJid, option, [dataForm allKeys]);
            [self decrementNameChange:roomJid];
            if(deleteOnError)
            {
                [self removeRoomFromCreating:roomJid];
                [self deleteMuc:roomJid withBookmarksUpdate:NO keepBuddylistEntry:NO];
            }
            [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Could not configure (new) group '%@': config option '%@' not available!", @""), roomJid, option] forMuc:roomJid withNode:nil andIsSevere:YES];
            return;
        }
        else
            dataForm[option] = mandatoryOptions[option];
    }
    
    //these config options are optional but most of them should be supported by all modern servers
    for(NSString* option in optionalOptions)
    {
        if(dataForm[option])
            dataForm[option] = optionalOptions[option];
        else
            DDLogWarn(@"Ignoring optional config option for room '%@': %@", roomJid, option);
    }
    
    //reconfigure the room
    dataForm.type = @"submit";
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType to:roomJid];
    [query setRoomConfig:dataForm];
    [_account sendIq:query withHandler:$newHandlerWithInvalidation(self, handleRoomConfigResult, handleRoomConfigResultInvalidation, $ID(roomJid), $ID(mandatoryOptions), $ID(optionalOptions), $BOOL(deleteOnError), $BOOL(joinOnSuccess))];
$$

$$instance_handler(handleRoomConfigResultInvalidation, account.mucProcessor, $$ID(xmpp*, account), $$ID(NSString*, roomJid), $$ID(NSDictionary*, mandatoryOptions), $$ID(NSDictionary*, optionalOptions), $$BOOL(deleteOnError))
    [self decrementNameChange:roomJid];
    if(deleteOnError)
    {
        DDLogError(@"Config form submit failed, removing muc '%@' from _creating...", roomJid);
        [self removeRoomFromCreating:roomJid];
        [self deleteMuc:roomJid withBookmarksUpdate:NO keepBuddylistEntry:NO];
    }
    else
        DDLogError(@"Config form submit failed for muc '%@'!", roomJid);
    [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Could not configure group '%@': please try again", @""), roomJid] forMuc:roomJid withNode:nil andIsSevere:YES];
$$

$$instance_handler(handleRoomConfigResult, account.mucProcessor, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, roomJid), $$ID(NSDictionary*, mandatoryOptions), $$ID(NSDictionary*, optionalOptions), $$BOOL(deleteOnError), $$BOOL(joinOnSuccess))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Failed to submit room config form of '%@': %@", roomJid, [iqNode findFirst:@"error"]);
        [self decrementNameChange:roomJid];
        if(deleteOnError)
        {
            [self removeRoomFromCreating:roomJid];
            [self deleteMuc:roomJid withBookmarksUpdate:NO keepBuddylistEntry:NO];
        }
        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Could not configure group '%@'", @""), roomJid] forMuc:roomJid withNode:iqNode andIsSevere:YES];
        return;
    }
    
    //isaCloud: some servers do not make the room persistent even if we asked for it (or do not offer the option at all)
    //--> check the disco features of the configured room and warn the user if it is not persistent
    XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType to:roomJid];
    [discoInfo setDiscoInfoNode];
    [account sendIq:discoInfo withResponseHandler:^(XMPPIQ* response) {
        BOOL persistent = NO;
        for(NSDictionary* feature in [response find:@"{http://jabber.org/protocol/disco#info}query/feature@@"])
            if([feature[@"var"] isEqualToString:@"muc_persistent"])
                persistent = YES;
        if(!persistent)
        {
            DDLogWarn(@"Room '%@' was configured but the server does not report it as persistent", roomJid);
            [HelperTools postError:[NSString stringWithFormat:NSLocalizedString(@"The server did not confirm that the group '%@' is permanent. It may disappear when everyone leaves.", @""), roomJid] withNode:nil andAccount:account andIsSevere:NO];
        }
        [self continueAfterRoomConfig:roomJid joinOnSuccess:joinOnSuccess];
    } andErrorHandler:^(XMPPIQ* error) {
        DDLogWarn(@"Could not check persistence of room '%@': %@", roomJid, [error findFirst:@"error"]);
        [self continueAfterRoomConfig:roomJid joinOnSuccess:joinOnSuccess];
    }];
$$

//isaCloud: last step of creating a group, after its configuration was submitted
-(void) continueAfterRoomConfig:(NSString*) roomJid joinOnSuccess:(BOOL) joinOnSuccess
{
    //don't call success handler if we are only "half-joined" (see comments below for what that means)
    if(joinOnSuccess)
    {
        //group is now properly configured and we are joined, but all the code handling a proper join was not run
        //--> join again to make sure everything is sane
        [self join:roomJid];
    }
    else
        [self callSuccessUIHandlerForMuc:roomJid];
}


-(void) handleStatusCodes:(XMPPStanza*) node
{
    NSSet* presenceCodes = [[NSSet alloc] initWithArray:[node find:@"/{jabber:client}presence/{http://jabber.org/protocol/muc#user}x/status@code|int"]];
    NSSet* messageCodes = [[NSSet alloc] initWithArray:[node find:@"/{jabber:client}message/{http://jabber.org/protocol/muc#user}x/status@code|int"]];
    NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:node.fromUser forAccount:_account.accountID];
    
    //handle status codes allowed in presences AND messages
    NSMutableSet* unhandledStatusCodes = [NSMutableSet new];
    NSMutableSet* jointCodes = [presenceCodes mutableCopy];
    [jointCodes unionSet:messageCodes];
    BOOL selfPrecenceHandled = NO;
    for(NSNumber* code in jointCodes)
            switch([code intValue])
            {
                //muc service changed our nick
                case 210:
                {
                    //check if we haven't joined already (this status code is only valid while entering a room)
                    if([self isJoining:node.fromUser])
                    {
                        //update nick in database
                        DDLogInfo(@"Updating muc %@ nick in database to nick provided by server: '%@'...", node.fromUser, node.fromResource);
                        [[DataLayer sharedInstance] updateOwnNickName:node.fromResource forMuc:node.fromUser forAccount:_account.accountID];
                        
                        DDLogDebug(@"Updating muc contact...");
                        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
                            @"contact": [MLContact createContactFromJid:node.fromUser andAccountID:_account.accountID]
                        }];
                    }
                    break;
                }
                //isaCloud: the occupant (a session of ours, or somebody else) changed the nick: nothing to do here, the participants are updated by the presence handling
                case 303:
                    break;
                //banned from room
                case 301:
                {
                    DDLogDebug(@"user '%@' got banned from room %@", node.fromResource, node.fromUser);
                    if([nick isEqualToString:node.fromResource])
                    {
                        DDLogDebug(@"got banned from room %@", node.fromUser);
                        [self removeRoomFromJoining:node.fromUser];
                        [self deleteMuc:node.fromUser withBookmarksUpdate:YES keepBuddylistEntry:NO];
                        selfPrecenceHandled = YES;
                        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"You got banned from group/channel: %@", @""), node.fromUser] forMuc:node.fromUser withNode:node andIsSevere:YES];
                        
                        DDLogDebug(@"Updating muc contact...");
                        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
                            @"contact": [MLContact createContactFromJid:node.fromUser andAccountID:_account.accountID]
                        }];
                    }
                    break;
                }
                //kicked from room
                case 307:
                {
                    /*
                     * To quote XEP-0045:
                     * Note: Some server implementations additionally include a 307 status code (signifying a 'kick', i.e. a forced ejection from the room). This is generally not advisable, as these types of disconnects may be frequent in the presence of poor network conditions and they are not linked to any user (e.g. moderator) action that the 307 code usually indicates. It is therefore recommended for the client to ignore the 307 code if a 333 status code is present.
                     */
                    if(![jointCodes containsObject:@333])
                    {
                        DDLogDebug(@"user '%@' got kicked from room %@", node.fromResource, node.fromUser);
                        if([nick isEqualToString:node.fromResource])
                        {
                            DDLogDebug(@"got kicked from room %@", node.fromUser);
                            [self removeRoomFromJoining:node.fromUser];
                            [self deleteMuc:node.fromUser withBookmarksUpdate:YES keepBuddylistEntry:NO];
                            selfPrecenceHandled = YES;
                            [self handleError:[NSString stringWithFormat:NSLocalizedString(@"You got kicked from group/channel: %@", @""), node.fromUser] forMuc:node.fromUser withNode:node andIsSevere:YES];
                            
                            DDLogDebug(@"Updating muc contact...");
                            [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
                                @"contact": [MLContact createContactFromJid:node.fromUser andAccountID:_account.accountID]
                            }];
                        }
                    }
                    else
                        DDLogWarn(@"Ignoring 307 status code because code 333 is present, too...");
                    break;
                }
                //removed because of affiliation change
                case 321:
                {
                    //only handle this and rejoin, if we did not get removed from a members-only room
                    if(![jointCodes containsObject:@322])
                    {
                        DDLogDebug(@"user '%@' got affiliation changed for room %@", node.fromResource, node.fromUser);
                        if([nick isEqualToString:node.fromResource])
                        {
                            DDLogDebug(@"got own affiliation change for room %@", node.fromUser);
                            //check if we are still in the room (e.g. loss of membership status in public channel or admin to member degradation)
                            if([[DataLayer sharedInstance] getParticipantForNick:node.fromResource inRoom:node.fromUser forAccountID:_account.accountID] == nil)
                            {
                                DDLogInfo(@"Got removed from room...");
                                [self removeRoomFromJoining:node.fromUser];
                                [self deleteMuc:node.fromUser withBookmarksUpdate:YES keepBuddylistEntry:YES];
                                selfPrecenceHandled = YES;
                                [self handleError:[NSString stringWithFormat:NSLocalizedString(@"You got removed from group/channel: %@", @""), node.fromUser] forMuc:node.fromUser withNode:node andIsSevere:YES];
                                
                                DDLogDebug(@"Updating muc contact...");
                                [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
                                    @"contact": [MLContact createContactFromJid:node.fromUser andAccountID:_account.accountID]
                                }];
                            }
                        }
                    }
                    break;
                }
                //removed because room is now members only (an we are not a member)
                case 322:
                {
                    DDLogDebug(@"user '%@' got removed from members-only room %@", node.fromResource, node.fromUser);
                    if([nick isEqualToString:node.fromResource])
                    {
                        DDLogDebug(@"got removed from members-only room %@", node.fromUser);
                        [self removeRoomFromJoining:node.fromUser];
                        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Kicked, because group/channel is now members-only: %@", @""), node.fromUser] forMuc:node.fromUser withNode:node andIsSevere:YES];
                        [self deleteMuc:node.fromUser withBookmarksUpdate:YES keepBuddylistEntry:YES];
                        selfPrecenceHandled = YES;
                        
                        DDLogDebug(@"Updating muc contact...");
                        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
                            @"contact": [MLContact createContactFromJid:node.fromUser andAccountID:_account.accountID]
                        }];
                    }
                    break;
                }
                //removed because of system shutdown
                case 332:
                {
                    DDLogDebug(@"user '%@' got removed from room %@ because of system shutdown", node.fromResource, node.fromUser);
                    if([nick isEqualToString:node.fromResource])
                    {
                        DDLogDebug(@"got removed from room %@ because of system shutdown", node.fromUser);
                        [self removeRoomFromJoining:node.fromUser];
                        selfPrecenceHandled = YES;
                        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Kicked from group/channel, because of system shutdown: %@", @""), node.fromUser] forMuc:node.fromUser withNode:node andIsSevere:YES];
                        
                        DDLogDebug(@"Updating muc contact...");
                        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
                            @"contact": [MLContact createContactFromJid:node.fromUser andAccountID:_account.accountID]
                        }];
                    }
                    break;
                }
                default:
                    [unhandledStatusCodes addObject:code];
            }
    
    //handle presence stanzas
    if(presenceCodes && [presenceCodes count])
    {
        for(NSNumber* code in presenceCodes)
            switch([code intValue])
            {
                //room created and needs configuration now
                case 100:
                    DDLogVerbose(@"This room is non-anonymous: everybody can see all jids...");
                    break;
                case 110:
                    break;      //ignore self-presence status handled below
                case 201:
                {
                    if(![presenceCodes containsObject:@110])
                    {
                        DDLogError(@"Got 'muc needs configuration' status code (201) without self-presence, ignoring!");
                        break;
                    }
                    if(![self isCreating:node.fromUser])
                    {
                        DDLogError(@"Got 'muc needs configuration' status code (201) without this muc currently being created, ignoring: %@", node.fromUser);
                        break;
                    }
                    
                    //now configure newly created locked room
                    [self configureMuc:node.fromUser withMandatoryOptions:_mandatoryGroupConfigOptions andOptionalOptions:_optionalGroupConfigOptions deletingMucOnError:YES andJoiningMucOnSuccess:YES];
                    
                    //stop processing here to not trigger the "successful join" code below
                    //we will trigger this code by a "second" join presence once the room was created and is not locked anymore
                    return;
                    break;
                }
                default:
                    //only log errors for status codes not already handled by our joint handling above
                    if([unhandledStatusCodes containsObject:code])
                        DDLogWarn(@"Got unhandled muc status code in presence from %@: %@", node.from, code);
                    break;
            }
        
        //this is a self-presence (marking the end of the presence flood if we are in joining state)
        //handle this code last because it may reset _joining
        if([presenceCodes containsObject:@110] && !selfPrecenceHandled)
        {
            //check if we have joined already (we handle only non-joining self-presences here)
            //joining self-presences are handled below
            if(![self isJoining:node.fromUser])
            {
                DDLogInfo(@"Got non-joining muc presence for %@...", node.fromUser);
                
                //handle muc destroys, but ignore other non-joining self-presences for now
                //(normally these have an additional status code that was already handled in the switch statement above
                if([node check:@"/<type=unavailable>/{http://jabber.org/protocol/muc#user}x/destroy"])
                {
                    //don't handle this error if we ourselves are destroying this room
                    if(![self isDestroying:node.fromUser])
                    {
                        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Group/Channel got destroyed: %@", @""), node.fromUser] forMuc:node.fromUser withNode:node andIsSevere:YES];
                        [self deleteMuc:node.fromUser withBookmarksUpdate:YES keepBuddylistEntry:YES];
                        
                        DDLogDebug(@"Updating muc contact...");
                        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
                            @"contact": [MLContact createContactFromJid:node.fromUser andAccountID:_account.accountID]
                        }];
                    }
                }
            }
            else
            {
                DDLogInfo(@"Successfully joined muc %@...", node.fromUser);
                
                //we are joined now, remove from joining list and add to joined list
                @synchronized(_stateLockObject) {
                    [self removeRoomFromJoining:node.fromUser];
                    [_joined addObject:node.fromUser];
                }
                
                //we joined successfully --> add muc to our favorites (this will use the already up to date nick from buddylist db table)
                //and update bookmarks if this was the first time we joined this muc
                [[DataLayer sharedInstance] addMucFavorite:node.fromUser forAccountID:_account.accountID andMucNick:nil];
                @synchronized(_stateLockObject) {
                    DDLogVerbose(@"_firstJoin set: %@\n_noUpdateBookmarks set: %@", _firstJoin, _noUpdateBookmarks);
                    //only update bookmarks on first join AND if not requested otherwise (batch join etc.)
                    if([_firstJoin containsObject:node.fromUser] && ![_noUpdateBookmarks containsObject:node.fromUser])
                        [self updateBookmarks];
                    [_firstJoin removeObject:node.fromUser];
                    [_noUpdateBookmarks removeObject:node.fromUser];
                }
                
                //update own occupant-id in buddylist
                NSString* occupantId = nil;
                @synchronized(_stateLockObject) {
                    if([_roomFeatures[node.fromUser] containsObject:@"urn:xmpp:occupant-id:0"])
                        occupantId = [node findFirst:@"{urn:xmpp:occupant-id:0}occupant-id@id"];
                }
                [[DataLayer sharedInstance] updateOwnOccupantID:occupantId forMuc:node.fromUser onAccountID:_account.accountID];
                
                DDLogDebug(@"Updating muc contact...");
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
                    @"contact": [MLContact createContactFromJid:node.fromUser andAccountID:_account.accountID]
                }];
                
                [self logMembersOfMuc:node.fromUser];
                
                //load members/admins/owners list (this has to be done *after* joining the muc to not get auth errors)
                DDLogInfo(@"Querying outcast/member/admin/owner lists for muc %@...", node.fromUser);
                for(NSString* type in @[kMucAffiliationOutcast, kMucAffiliationMember, kMucAffiliationAdmin, kMucAffiliationOwner])
                {
                    XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType to:node.fromUser];
                    [discoInfo setMucListQueryFor:type];
                    [_account sendIq:discoInfo withHandler:$newHandler(self, handleMembersList, $ID(type))];
                }
                
                [self callSuccessUIHandlerForMuc:node.fromUser];
                
                //MAYBE TODO: send out notification indicating we joined that room
                
                //query muc-mam for new messages
                BOOL supportsMam = NO;
                @synchronized(_stateLockObject) {
                    if(_roomFeatures[node.fromUser] && [_roomFeatures[node.fromUser] containsObject:@"urn:xmpp:mam:2"])
                        supportsMam = YES;
                }
                if(supportsMam)
                {
                    DDLogInfo(@"Muc %@ supports mam:2...", node.fromUser);
                    
                    //query mam since last received stanza ID because we could not resume the smacks session
                    //(we would not have landed here if we were able to resume the smacks session)
                    //this will do a catchup of everything we might have missed since our last connection
                    //we possibly receive sent messages, too (this will update the stanzaid in database and gets deduplicate by messageid,
                    //which is guaranteed to be unique (because monal uses uuids for outgoing messages)
                    NSString* lastStanzaId = [[DataLayer sharedInstance] lastStanzaIdForMuc:node.fromUser andAccount:_account.accountID];
                    [_account delayIncomingMessageStanzasForArchiveJid:node.fromUser];
                    if(lastStanzaId)
                        [self queryMamCatchupForMuc:node.fromUser afterStanzaId:lastStanzaId];
                    else
                    {
                        XMPPIQ* mamQuery = [[XMPPIQ alloc] initWithType:kiqSetType to:node.fromUser];
                        DDLogInfo(@"Querying muc mam:2 archive for latest stanzaid to prime database");
                        [mamQuery setMAMQueryForLatestId];
                        [_account sendIq:mamQuery withHandler:$newHandler(self, handleMamResponseWithLatestId)];
                    }
                }
                
                //we don't need to force saving of our new state because once this incoming presence gets counted by smacks the whole state will be saved
            }
        }
    }
    //handle message stanzas
    else if(messageCodes && [messageCodes count])
    {
        for(NSNumber* code in messageCodes)
            switch([code intValue])
            {
                //config changes
                case 102:
                case 103:
                case 104:
                /*
                 * If room logging is now enabled, status code 170.
                 * If room logging is now disabled, status code 171.
                 * If the room is now non-anonymous, status code 172.
                 * If the room is now semi-anonymous, status code 173.
                 */
                case 170:
                case 171:
                case 172:
                case 173:
                {
                    DDLogInfo(@"Muc config of %@ changed, sending new disco info query to reload muc config...", node.fromUser);
                    [self sendDiscoQueryFor:node.from withJoin:NO andBookmarksUpdate:NO];
                    break;
                }
                default:
                    //only log errors for status codes not already handled by our joint handling above
                    if([unhandledStatusCodes containsObject:code])
                        DDLogWarn(@"Got unhandled muc status code in message from %@: %@", node.from, code);
                    break;
            }
    }
}

$$instance_handler(handleCreateTimeout, account.mucProcessor, $$ID(xmpp*, account), $$ID(NSString*, room), $$ID(NSNumber*, timerId))
    @synchronized(_stateLockObject) {
        MLAssert([self isCreating:room] && [timerId isEqual:_creating[room]], @"Spurious idle timer firing!", (@{
            @"currentTimer": nilWrapper(_creating[room]),
            @"expectedTimer": nilWrapper(timerId),
        }));
        DDLogWarn(@"Timeout while creating muc '%@'...", room);
        [self removeRoomFromCreating:room];
        [self deleteMuc:room withBookmarksUpdate:NO keepBuddylistEntry:NO];
    }
    [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Could not create group '%@': timeout", @""), room] forMuc:room withNode:nil andIsSevere:YES];
$$

//isaCloud: first MUC service of the server (gateways excluded)
-(BOOL) isUsableMucService:(NSString*) jid
{
    // Do not use gateways
    return ![_account.connectionProperties.conferenceServers[jid] check:@"identity<category=gateway>"]
        && [_account.connectionProperties.conferenceServers[jid] check:@"identity<category=conference>"]
        && [_account.connectionProperties.conferenceServers[jid] check:@"identity<type=text>"];
}

-(NSString* _Nullable) mucServiceJid
{
    NSString* ownComponent = _ownMucComponents[[_account.connectionProperties.identity.domain lowercaseString]];
    if(ownComponent != nil)
        for(NSString* jid in _account.connectionProperties.conferenceServers)
            if([jid isEqualToString:ownComponent] && [self isUsableMucService:jid])
                return jid;
    //not one of our servers: the first usable service advertised, like Monal does
    for(NSString* jid in _account.connectionProperties.conferenceServers)
        if([self isUsableMucService:jid])
            return jid;
    return nil;
}

//isaCloud: one MUC service, all of its pages (XEP-0059), appended to channels; completion gets NO when the service could not be queried
-(void) fetchPublicChannelsOf:(NSString*) mucServer after:(NSString* _Nullable) after page:(NSUInteger) page intoChannels:(NSMutableArray*) channels completion:(void (^)(BOOL success)) completion
{
    static const NSUInteger pageSize = 50;
    static const NSUInteger maxPages = 200;      //safety net against servers that never end their paging
    XMPPIQ* discoItems = [[XMPPIQ alloc] initWithType:kiqGetType to:mucServer];
    [discoItems setDiscoItemNodeWithAfter:after maxItems:pageSize];
    [_account sendIq:discoItems withResponseHandler:^(XMPPIQ* response) {
        NSArray* items = [response find:@"{http://jabber.org/protocol/disco#items}query/item@@"];
        for(NSDictionary* item in items)
            [channels addObject:@{
                @"jid": item[@"jid"],
                @"name": item[@"name"] ?: item[@"jid"]
            }];
        NSString* next = [response findFirst:@"{http://jabber.org/protocol/disco#items}query/{http://jabber.org/protocol/rsm}set/last#"];
        //stop at the last page: no cursor, a short page, or the page cap
        if(next == nil || [items count] < pageSize || page + 1 >= maxPages)
            completion(YES);
        else
            [self fetchPublicChannelsOf:mucServer after:next page:page + 1 intoChannels:channels completion:completion];
    } andErrorHandler:^(XMPPIQ* error) {
        DDLogWarn(@"Public channel query to %@ failed: %@", mucServer, [error findFirst:@"error"]);
        completion(NO);
    }];
}

-(void) queryPublicChannelsWithCompletion:(monal_id_block_t) completion
{
    //query every MUC service the server advertises (gateways excluded) and merge the rooms they list
    NSMutableArray* services = [NSMutableArray new];
    for(NSString* jid in _account.connectionProperties.conferenceServers)
    {
        if(![_account.connectionProperties.conferenceServers[jid] check:@"identity<category=gateway>"]
          && [_account.connectionProperties.conferenceServers[jid] check:@"identity<category=conference>"]
          && [_account.connectionProperties.conferenceServers[jid] check:@"identity<type=text>"])
            [services addObject:jid];
    }
    DDLogInfo(@"Public channel query on MUC services: %@", services);
    if([services count] == 0)
    {
        completion(NSNull.null);
        return;
    }
    //all services are queried in parallel; the completion runs once, after the last one answered
    dispatch_group_t group = dispatch_group_create();
    NSObject* lock = [NSObject new];
    __block NSUInteger failures = 0;
    NSMutableArray* channels = [NSMutableArray new];
    for(NSString* mucServer in services)
    {
        dispatch_group_enter(group);
        NSMutableArray* serviceChannels = [NSMutableArray new];
        [self fetchPublicChannelsOf:mucServer after:nil page:0 intoChannels:serviceChannels completion:^(BOOL success) {
            @synchronized(lock) {
                if(success)
                    [channels addObjectsFromArray:serviceChannels];
                else
                    failures++;
            }
            dispatch_group_leave(group);
        }];
    }
    //isaCloud: reported only once, either when all services answered or when the timeout hits (a server that never answers must not leave the list loading forever)
    __block BOOL reported = NO;
    void (^report)(id) = ^(id result) {
        if(reported)
            return;
        reported = YES;
        completion(result);
    };
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if(failures == [services count])
            report(NSNull.null);
        else
            report(channels);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        DDLogWarn(@"Public channel query timed out, services: %@", services);
        report(NSNull.null);
    });
}

-(void) queryMemberCountOfRoom:(NSString*) room completion:(monal_id_block_t) completion
{
    XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType to:room];
    [discoInfo setDiscoInfoNode];
    [_account sendIq:discoInfo withResponseHandler:^(XMPPIQ* response) {
        for(MLXMLNode* field in [response find:@"{http://jabber.org/protocol/disco#info}query/{jabber:x:data}x/field"])
        {
            if([field.attributes[@"var"] isEqualToString:@"muc#roominfo_occupants"])
            {
                completion(@([[field findFirst:@"value#"] integerValue]));
                return;
            }
        }
        completion(NSNull.null);
    } andErrorHandler:^(XMPPIQ* error) {
        completion(NSNull.null);
    }];
}

-(void) queryAvatarOfRoom:(NSString*) room completion:(monal_id_block_t) completion
{
    XMPPIQ* vcardQuery = [[XMPPIQ alloc] initWithType:kiqGetType to:room];
    [vcardQuery setVcardQuery];
    [_account sendIq:vcardQuery withResponseHandler:^(XMPPIQ* response) {
        NSData* imageData = [response findFirst:@"{vcard-temp}vCard/PHOTO/BINVAL#|base64"];
        if(imageData)
            completion(imageData);
        else
            completion(NSNull.null);
    } andErrorHandler:^(XMPPIQ* error) {
        completion(NSNull.null);
    }];
}

-(NSString* _Nullable) generateMucJid
{
    NSString* mucServer = [self mucServiceJid];
    if(mucServer == nil)
        return nil;
    NSString* node = [self generateSpeakableGroupNode];
    node = [node stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    NSString* room = [[NSString stringWithFormat:@"%@@%@", node, mucServer] lowercaseString];
    return room;
}

-(NSString* _Nullable) createGroup:(NSString*) room
{
    if([[DataLayer sharedInstance] isBuddyMuc:room forAccount:_account.accountID])
    {
        DDLogWarn(@"Cannot create muc already existing in our buddy list, checking if we are still joined and join if needed...");
        [self ping:room];
        return nil;
    }
    
    //remove old non-muc contact from contactlist (we don't want mucs as normal contacts on our (server) roster and shadowed in monal by the real muc contact)
    NSDictionary* existingContactDict = [[DataLayer sharedInstance] contactDictionaryForUsername:room forAccount:_account.accountID];
    if(existingContactDict != nil)
    {
        MLContact* existingContact = [MLContact createContactFromJid:room andAccountID:_account.accountID];
        DDLogVerbose(@"CreateMUC: Removing already existing contact (%@) having raw db dict: %@", existingContact, existingContactDict);
        [_account removeFromRoster:existingContact];
    }
    //add new muc buddy (potentially deleting a non-muc buddy having the same jid)
    NSString* nick = [self calculateNickForMuc:room];
    DDLogInfo(@"CreateMUC: Adding new muc %@ using nick '%@' to buddylist...", room, nick);
    [[DataLayer sharedInstance] initMuc:room forAccountID:_account.accountID andMucNick:nick];
    
    DDLogInfo(@"Trying to create muc '%@' with nick '%@' on account %@...", room, nick, _account);
    @synchronized(_stateLockObject) {
        //add room to "currently creating" list (and remove any present idle timer for this room)
        [[DataLayer sharedInstance] delIdleTimerWithId:_creating[room]];
        //add idle timer to display error if we did not receive the reflected create presence after 30 idle seconds
        //this will make sure the spinner ui will not spin indefinitely when adding a channel via ui
        NSNumber* timerId = [[DataLayer sharedInstance] addIdleTimerWithTimeout:@30 andHandler:$newHandler(self, handleCreateTimeout, $ID(room)) onAccountID:_account.accountID];
        _creating[room] = timerId;
        //we don't need to force saving of our new state because once this outgoing create presence gets handled by smacks the whole state will be saved
    }
    XMPPPresence* presence = [XMPPPresence new];
    [presence createRoom:room withNick:nick];
    [_account send:presence];
    
    return room;
}

-(void) destroyRoom:(NSString*) room
{
    MLAssert([[DataLayer sharedInstance] isBuddyMuc:room forAccount:_account.accountID], @"Cannot destroy non-muc!", (@{@"room": room}));
    
    @synchronized(_stateLockObject) {
        [_destroying addObject:room];
    }
    
    XMPPIQ* iqNode = [[XMPPIQ alloc] initWithType:kiqSetType to:room];
    [iqNode addChildNode:[[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"http://jabber.org/protocol/muc#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"destroy" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"reason" andData:@"Groupchat got destroyed"]
        ] andData:nil],
    ] andData:nil]];
    [_account sendIq:iqNode withHandler:$newHandlerWithInvalidation(self, handleRoomDestroyResult, handleRoomDestroyResultInvalidation, $ID(room))];
}

$$instance_handler(handleRoomDestroyResultInvalidation, account.mucProcessor, $$ID(xmpp*, account), $$ID(NSString*, room))
    DDLogError(@"Could not destroy room '%@' on account %@", room, account);
    @synchronized(_stateLockObject) {
        [_destroying removeObject:room];
    }
    [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Failed to destroy group/channel '%@': please try again", @""), room] forMuc:room withNode:nil andIsSevere:YES];
$$

$$instance_handler(handleRoomDestroyResult, account.mucProcessor, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, room))
    @synchronized(_stateLockObject) {
        [_destroying removeObject:room];
    }
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Failed to destroy room '%@' on account %@: %@", room, account, [iqNode findFirst:@"error"]);
        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Failed to destroy group/channel '%@'", @""), room] forMuc:room withNode:iqNode andIsSevere:YES];
        return;
    }
    
    DDLogInfo(@"Successfully destroyed room '%@' on account %@", room, account);
    if([self getUIHandlerForMuc:room] != nil)
    {
        [self callSuccessUIHandlerForMuc:room withCallback:^{
            //don't even keep our bookmark in this case
            [self deleteMuc:room withBookmarksUpdate:YES keepBuddylistEntry:NO];
        }];
    }
    else
    {
        //don't even keep our bookmark in this case
        //this will handled by the ui handler callback if the ui was used to destroy this room and must be handled here otherwise
        [self deleteMuc:room withBookmarksUpdate:YES keepBuddylistEntry:NO];
    }
$$

-(void) join:(NSString*) room
{
    [self sendDiscoQueryFor:room withJoin:YES andBookmarksUpdate:YES];
}

-(void) leave:(NSString*) room withBookmarksUpdate:(BOOL) updateBookmarks keepBuddylistEntry:(BOOL) keepBuddylistEntry
{
    room = [room lowercaseString];
    NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:_account.accountID];
    if(nick == nil)
    {
        DDLogError(@"Cannot leave room '%@' on account %@ because nick is nil!", room, _account);
        return;
    }
    @synchronized(_stateLockObject) {
        if(_joining[room] != nil)
        {
            DDLogInfo(@"Aborting join of room '%@' on account %@", room, _account);
            [self removeRoomFromJoining:room];
        }
    }
    DDLogInfo(@"Leaving room '%@' on account %@ using nick '%@'...", room, _account, nick);
    //send unsubscribe even if we are not fully joined (join aborted), just to make sure we *really* leave ths muc
    XMPPPresence* presence = [XMPPPresence new];
    [presence leaveRoom:room withNick:nick];
    [_account send:presence];
    
    //delete muc from favorites table and update bookmarks if requested
    [self deleteMuc:room withBookmarksUpdate:updateBookmarks keepBuddylistEntry:keepBuddylistEntry];
}

-(void) sendDiscoQueryFor:(NSString*) roomJid withJoin:(BOOL) join andBookmarksUpdate:(BOOL) updateBookmarks
{
    if(roomJid == nil || _account == nil)
        @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Room jid or account must not be nil!" userInfo:nil];
    roomJid = [roomJid lowercaseString];
    DDLogInfo(@"Querying disco for muc %@...", roomJid);
    //mark room as "joining" as soon as possible to make sure we can handle join "aborts" (e.g. when processing bookmark updates while a joining disco query is already in flight)
    //this will fix race condition that makes us join a muc directly after it got removed from our favorites table and leaved through a bookmark update
    if(join)
    {
        @synchronized(_stateLockObject) {
            //don't join twice
            if(_joining[roomJid] != nil)
            {
                DDLogInfo(@"Already joining muc %@, not doing it twice", roomJid);
                return;
            }
            //add room to "currently joining" list (without any idle timer yet, because the iq handling will timeout the disco iq already)
            _joining[roomJid] = @(-1);      //TODO
            //we don't need to force saving of our new state because once this outgoing iq query gets handled by smacks the whole state will be saved
        }
    }
    XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType to:roomJid];
    [discoInfo setDiscoInfoNode];
    [_account sendIq:discoInfo withHandler:$newHandlerWithInvalidation(self, handleDiscoResponse, handleDiscoResponseInvalidation, $ID(roomJid), $BOOL(join), $BOOL(updateBookmarks))];
}

-(void) pingAllMucs
{
    if([[NSDate date] timeIntervalSinceDate:_lastPing] < MUC_PING)
    {
        DDLogInfo(@"Not pinging all mucs, last ping was less than %d seconds ago: %@", MUC_PING, _lastPing);
        return;
    }
    for(NSString* room in [[DataLayer sharedInstance] listMucsForAccount:_account.accountID])
        [self ping:room withLastPing:_lastPing];
    _lastPing = [NSDate date];
}

-(void) ping:(NSString*) roomJid
{
    [self ping:roomJid withLastPing:nil];
}

-(void) ping:(NSString*) roomJid withLastPing:(NSDate* _Nullable) lastPing
{
    if(![[DataLayer sharedInstance] isBuddyMuc:roomJid forAccount:_account.accountID])
    {
        DDLogWarn(@"Tried to muc-ping non-muc jid '%@', trying to join regularily with disco...", roomJid);
        [self removeRoomFromJoining:roomJid];
        //this will check if this jid really is not a muc and delete it fom favorites and bookmarks, if not (and join normally if it turns out is a muc after all)
        [self sendDiscoQueryFor:roomJid withJoin:YES andBookmarksUpdate:YES];
        return;
    }
    
    XMPPIQ* ping = [[XMPPIQ alloc] initWithType:kiqGetType to:roomJid];
    ping.toResource = [[DataLayer sharedInstance] ownNickNameforMuc:roomJid forAccount:_account.accountID];
    [ping setPing];
    //we don't need to handle this across smacks resumes or reconnects, because a new ping will be issued on the next smacks resume
    //(and full reconnets will rejoin all mucs anyways)
    [_account sendIq:ping withResponseHandler:^(XMPPIQ* result __unused) {
        DDLogInfo(@"Muc ping returned: we are still connected to %@, everything is fine", roomJid);
    } andErrorHandler:^(XMPPIQ* error) {
        if(error == nil)
        {
            DDLogWarn(@"Ping handler for %@ got invalidated, aborting ping...", roomJid);
            //make sure we try again without waiting another MUC_PING seconds, if possible (i.e. this ping was not triggered by ui)
            if(lastPing != nil)
                self->_lastPing = lastPing;
            return;
        }
        DDLogWarn(@"%@", [HelperTools extractXMPPError:error withDescription:@"Muc ping returned error"]);
        if([error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}not-acceptable"])
        {
            DDLogWarn(@"Ping failed with 'not-acceptable' --> we have to re-join %@", roomJid);
            @synchronized(self->_stateLockObject) {
                [self removeRoomFromJoining:roomJid];
            }
            //check if muc is still in our favorites table before we try to join it (could be deleted by a bookmarks update just after we sent out our ping)
            //this has to be done to avoid such a race condition that would otherwise re-add the muc back
            if([self checkIfStillBookmarked:roomJid])
                [self sendDiscoQueryFor:roomJid withJoin:YES andBookmarksUpdate:YES];
            else
                DDLogWarn(@"Not re-joining because muc %@ got removed from favorites table in the meantime", roomJid);
        }
        else if(
            [error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}service-unavailable"] ||
            [error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}feature-not-implemented"]
        )
        {
            DDLogInfo(@"The client is joined to %@, but the pinged client does not implement XMPP Ping (XEP-0199) --> do nothing", roomJid);
        }
        else if([error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}item-not-found"])
        {
            DDLogInfo(@"The client is joined to %@, but the occupant just changed their name (e.g. initiated by a different client) --> do nothing", roomJid);
        }
        else if(
            [error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}remote-server-not-found"] ||
            [error check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}remote-server-timeout"]
        )
        {
            DDLogError(@"The remote server for room %@ is unreachable for unspecified reasons; this can be a temporary network failure or a server outage. No decision can be made based on this; Treat like a timeout --> do nothing", roomJid);
        }
        else
        {
            DDLogWarn(@"Any other error happened: The client is probably not joined to %@ any more. It should perform a re-join. --> we have to re-join", roomJid);
            @synchronized(self->_stateLockObject) {
                [self removeRoomFromJoining:roomJid];
            }
            //check if muc is still in our favorites table before we try to join it (could be deleted by a bookmarks updae just after we sent out our ping)
            //this has to be done to avoid such a race condition that would otherwise re-add the muc back
            if([self checkIfStillBookmarked:roomJid])
                [self sendDiscoQueryFor:roomJid withJoin:YES andBookmarksUpdate:YES];
            else
                DDLogWarn(@"Not re-joining %@ because this muc got removed from favorites table in the meantime", roomJid);
        }
    }];
}

-(void) inviteUser:(NSString*) jid inMuc:(NSString*) roomJid
{
    DDLogInfo(@"Directly inviting user '%@' to '%@'...", jid, roomJid);
    XMPPMessage* directInviteMsg = [[XMPPMessage alloc] initWithType:kMessageNormalType to:jid];
    [directInviteMsg addChildNode:[[MLXMLNode alloc] initWithElement:@"x" andNamespace:@"jabber:x:conference" withAttributes:@{
        @"jid": roomJid
    } andChildren:@[] andData:nil]];
    [directInviteMsg setStoreHint];
    [self->_account send:directInviteMsg];
}

-(AnyPromise*) setAffiliation:(NSString*) affiliation ofUser:(NSString*) jid inMuc:(NSString*) roomJid
{
    MLPromise* promise = [MLPromise new];
    
    DDLogInfo(@"Changing affiliation of '%@' in '%@' to '%@'", jid, roomJid, affiliation);
    XMPPIQ* updateIq = [[XMPPIQ alloc] initWithType:kiqSetType to:roomJid];
    [updateIq setMucAdminQueryWithAffiliation:affiliation forJid:jid];
    [_account sendIq:updateIq withHandler:$newHandlerWithInvalidation(self, handleAffiliationUpdateResult, handleAffiliationUpdateResultInvalidation, $ID(roomJid), $ID(jid), $ID(affiliation), $PROMISE(promise))];
    
    return [promise toAnyPromise];
}

$$instance_handler(handleAffiliationUpdateResultInvalidation, account.mucProcessor, $$ID(xmpp*, account), $$ID(NSString*, affiliation), $$ID(NSString*, jid), $$ID(NSString*, roomJid), $$PROMISE(promise))
    DDLogError(@"Failed to change affiliation of '%@' in '%@' to '%@'", jid, roomJid, affiliation);
    NSString* errorString = [NSString stringWithFormat:NSLocalizedString(@"Failed to change affiliation of '%@' in '%@' to '%@': please try again", @""), jid, roomJid, affiliation];
    [promise reject:[HelperTools getNSErrorFrom:nil withDescription:errorString]];
$$

$$instance_handler(handleAffiliationUpdateResult, account.mucProcessor, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, affiliation), $$ID(NSString*, jid), $$ID(NSString*, roomJid), $$PROMISE(promise))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Failed to change affiliation of '%@' in '%@' to '%@': %@", jid, roomJid, affiliation, [iqNode findFirst:@"error"]);
        NSString* errorString = [HelperTools extractXMPPError:iqNode withDescription:[NSString stringWithFormat:NSLocalizedString(@"Failed to change affiliation of '%@' in '%@' to '%@'", @""), jid, roomJid, affiliation]];
        [promise reject:[HelperTools getNSErrorFrom:iqNode withDescription:errorString]];
        return;
    }
    DDLogInfo(@"Successfully changed affiliation of '%@' in '%@' to '%@'", jid, roomJid, affiliation);
    [promise fulfill:nil];
$$

-(void) requestVoiceInMuc:(NSString*) roomJid
{
    DDLogInfo(@"Requesting voice in '%@'...", roomJid);
    XMPPMessage* msg = [[XMPPMessage alloc] initWithType:kMessageNormalType to:roomJid];
    [msg addChildNode:[[XMPPDataForm alloc] initWithType:@"submit" formType:@"http://jabber.org/protocol/muc#request" andDictionary:@{
        @"muc#role": @"participant",
    }]];
    [_account send:msg];
}

-(void) changeNameOfMuc:(NSString*) room to:(NSString*) name
{
    [self incrementNameChange:room];
    [self configureMuc:room withMandatoryOptions:@{
        @"muc#roomconfig_roomname": name,
    } andOptionalOptions:@{} deletingMucOnError:NO andJoiningMucOnSuccess:NO];
}

-(void) changeSubjectOfMuc:(NSString*) room to:(NSString*) subject
{
    XMPPMessage* msg = [[XMPPMessage alloc] initWithType:kMessageGroupChatType to:room];
    [msg addChildNode:[[MLXMLNode alloc] initWithElement:@"subject" andData:subject]];
    [_account send:msg];
}

-(AnyPromise*) publishAvatar:(UIImage* _Nullable) image forMuc:(NSString*) room
{
    MLPromise* promise = [MLPromise new];

    if(image == nil)
    {
        DDLogInfo(@"Removing avatar image for muc '%@'...", room);
        XMPPIQ* vcard = [[XMPPIQ alloc] initWithType:kiqSetType to:room];
        [vcard setRemoveVcardAvatar];
        [_account sendIq:vcard withHandler:$newHandlerWithInvalidation(self, handleAvatarPublishResult, handleAvatarPublishResultInvalidation, $ID(room), $PROMISE(promise))];
        return [promise toAnyPromise];
    }
    //should work for ejabberd >= 19.02 and prosody >= 0.11
    NSData* imageData = [HelperTools resizeAvatarImage:image withCircularMask:NO toMaxBase64Size:60000];
    NSString* imageHash = [HelperTools hexadecimalString:[HelperTools sha1:imageData]];
    
    DDLogInfo(@"Publishing avatar image for muc '%@' with hash %@", room, imageHash);
    XMPPIQ* vcard = [[XMPPIQ alloc] initWithType:kiqSetType to:room];
    [vcard setVcardAvatarWithData:imageData andType:@"image/jpeg"];
    [_account sendIq:vcard withHandler:$newHandlerWithInvalidation(self, handleAvatarPublishResult, handleAvatarPublishResultInvalidation, $ID(room), $PROMISE(promise))];

    return [promise toAnyPromise];
}

$$instance_handler(handleAvatarPublishResultInvalidation, account.mucProcessor, $$ID(xmpp*, account), $$ID(NSString*, room), $$PROMISE(promise))
    NSString* errorString = [NSString stringWithFormat:NSLocalizedString(@"Failed to publish avatar image for group/channel %@: please try again", @""), room];
    [promise reject:[HelperTools getNSErrorFrom:nil withDescription:errorString]];
$$

$$instance_handler(handleAvatarPublishResult, account.mucProcessor, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$PROMISE(promise))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Publishing avatar for muc '%@' returned error: %@", iqNode.fromUser, [iqNode findFirst:@"error"]);
        NSString* errorString = [NSString stringWithFormat:NSLocalizedString(@"Failed to publish avatar image for group/channel %@", @""), iqNode.fromUser];
        [promise reject:[HelperTools getNSErrorFrom:iqNode withDescription:errorString]];
        return;
    }
    DDLogInfo(@"Successfully published avatar for muc: %@", iqNode.fromUser);
    [promise fulfill:nil];
$$

$$instance_handler(handleDiscoResponseInvalidation, account.mucProcessor, $$ID(xmpp*, account), $$ID(NSString*, roomJid))
    [self decrementNameChange:roomJid];
    DDLogInfo(@"Removing muc '%@' from _joining...", roomJid);
    [self removeRoomFromJoining:roomJid];
$$

$$instance_handler(handleDiscoResponse, account.mucProcessor, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, roomJid), $$BOOL(join), $$BOOL(updateBookmarks))
    //no matter what the disco response is: we are not creating this muc anymore
    //either because we successfully created it and called join afterwards,
    //or because the user tried to simultaneously create and join this muc (the join has precendence in this case)
    BOOL wasCreating = [self isCreating:roomJid];
    [self removeRoomFromCreating:roomJid];
    
    
    if([iqNode check:@"/<type=error>/error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}gone"])
    {
        DDLogError(@"Querying muc info returned this muc isn't available anymore: %@", [iqNode findFirst:@"error"]);
        [self decrementNameChange:iqNode.fromUser];
        [self removeRoomFromJoining:iqNode.fromUser];
        
        //delete muc from favorites table to be sure we don't try to rejoin it and update bookmarks afterwards (to make sure this muc isn't accidentally left in our boomkmarks)
        //make sure to update remote bookmarks, even if updateBookmarks == NO
        //keep buddy list entry to allow users to read the last messages before the muc got deleted
        [self deleteMuc:iqNode.fromUser withBookmarksUpdate:YES keepBuddylistEntry:YES];
        
        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Group/Channel not available anymore: %@", @""), iqNode.fromUser] forMuc:iqNode.fromUser withNode:iqNode andIsSevere:YES];
        return;
    }
    
    if([iqNode check:@"/<type=error>/error<type=wait>"])
    {
        DDLogError(@"Querying muc info returned a temporary error: %@", [iqNode findFirst:@"error"]);
        [self decrementNameChange:iqNode.fromUser];
        [self removeRoomFromJoining:iqNode.fromUser];
        
        //do nothing: the error is only temporary (a s2s problem etc.), a muc ping will retry the join
        //this will keep the entry in local bookmarks table and remote bookmars
        //--> retry the join on mucPing or full login without smacks resume
        //this will also keep the buddy list entry
        //--> allow users to read the last messages before the muc got broken
        
        //only display an error banner, no notification (this is only temporary)
        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Temporary failure to enter Group/Channel: %@", @""), roomJid] forMuc:roomJid withNode:iqNode andIsSevere:NO];
        return;
    }
    else if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Querying muc info returned a persistent error: %@", [iqNode findFirst:@"error"]);
        [self decrementNameChange:iqNode.fromUser];
        [self removeRoomFromJoining:iqNode.fromUser];
        
        //delete muc from favorites table to be sure we don't try to rejoin it and update bookmarks afterwards (to make sure this muc isn't accidentally left in our boomkmarks)
        //make sure to update remote bookmarks, even if updateBookmarks == NO
        //keep buddy list entry to allow users to read the last messages before the muc got deleted/broken
        [self deleteMuc:iqNode.fromUser withBookmarksUpdate:YES keepBuddylistEntry:YES];
        
        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Failed to enter Group/Channel %@", @""), roomJid] forMuc:roomJid withNode:iqNode andIsSevere:YES];
        return;
    }
    
    //extract features
    NSSet* features = [NSSet setWithArray:[iqNode find:@"{http://jabber.org/protocol/disco#info}query/feature@var"]];
    
    //check if this is a muc
    if(![features containsObject:@"http://jabber.org/protocol/muc"])
    {
        DDLogError(@"muc disco returned that this jid is not a muc!");
        [self decrementNameChange:iqNode.fromUser];
        
        //delete muc from favorites table to be sure we don't try to rejoin it and update bookmarks afterwards (to make sure this muc isn't accidentally left in our boomkmarks)
        //make sure to update remote bookmarks, even if updateBookmarks == NO
        //keep buddy list entry to allow users to read the last messages before the muc got deleted/broken
        //AND: to not auto-delete contact list entries via malicious xmpp:?join links
        [self deleteMuc:iqNode.fromUser withBookmarksUpdate:YES keepBuddylistEntry:YES];
    
        [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Failed to enter Group/Channel %@: This is not a Group/Channel!", @""), iqNode.fromUser] forMuc:iqNode.fromUser withNode:nil andIsSevere:YES];
        return;
    }
    
    //force join if this isn't already recorded as muc in our database but as normal user or not recorded at all
    if(!join && ![[DataLayer sharedInstance] isBuddyMuc:iqNode.fromUser forAccount:_account.accountID])
        join = YES;
    
    //the join (join=YES) was aborted by a call to leave (isJoining: returns NO)
    if(join && ![self isJoining:iqNode.fromUser])
    {
        DDLogWarn(@"Ignoring muc disco result for '%@' on account %@: not joining anymore...", iqNode.fromUser, _account);
        [self decrementNameChange:iqNode.fromUser];
        return;
    }
        
    //extract further muc infos
    NSString* mucName = [iqNode findFirst:@"{http://jabber.org/protocol/disco#info}query/identity@name"];
    NSString* mucType = kMucTypeChannel;
    //both are needed for omemo, see discussion with holger 2021-01-02/03 -- Thilo Molitor
    //see also: https://docs.modernxmpp.org/client/groupchat/
    if([features containsObject:@"muc_nonanonymous"] && [features containsObject:@"muc_membersonly"])
        mucType = kMucTypeGroup;
    
    //update db with new infos
    BOOL isBuddyMuc = [[DataLayer sharedInstance] isBuddyMuc:iqNode.fromUser forAccount:_account.accountID];
    if(!isBuddyMuc || wasCreating)
    {
        if(!isBuddyMuc)
        {
            //remove old non-muc contact from contactlist (we don't want mucs as normal contacts on our (server) roster and shadowed in monal by the real muc contact)
            NSDictionary* existingContactDict = [[DataLayer sharedInstance] contactDictionaryForUsername:iqNode.fromUser forAccount:_account.accountID];
            if(existingContactDict != nil)
            {
                MLContact* existingContact = [MLContact createContactFromJid:iqNode.fromUser andAccountID:_account.accountID];
                DDLogVerbose(@"Removing already existing contact (%@) having raw db dict: %@", existingContact, existingContactDict);
                [_account removeFromRoster:existingContact];
            }
        }
        //add new muc buddy (potentially deleting a non-muc buddy having the same jid)
        NSString* nick = [self calculateNickForMuc:iqNode.fromUser];
        DDLogInfo(@"Adding new muc %@ using nick '%@' to buddylist...", iqNode.fromUser, nick);
        [[DataLayer sharedInstance] initMuc:iqNode.fromUser forAccountID:_account.accountID andMucNick:nick];
        //add this room to firstJoin list
        @synchronized(_stateLockObject) {
            [_firstJoin addObject:iqNode.fromUser];
            if(updateBookmarks == NO)
                [_noUpdateBookmarks addObject:iqNode.fromUser];
        }
        //make public channels "mention only" on first join
        if([kMucTypeChannel isEqualToString:mucType])
        {
            DDLogDebug(@"Configuring new muc %@ to be mention-only...", iqNode.fromUser);
            [[DataLayer sharedInstance] setMucAlertOnMentionOnly:iqNode.fromUser onAccount:_account.accountID];
        }
    }
    
    if(![mucType isEqualToString:[[DataLayer sharedInstance] getMucTypeOfRoom:iqNode.fromUser andAccount:_account.accountID]])
    {
        DDLogInfo(@"Configuring muc %@ to be of type '%@'...", iqNode.fromUser, mucType);
        [[DataLayer sharedInstance] updateMucTypeTo:mucType forRoom:iqNode.fromUser andAccount:_account.accountID];
    }
    else
        DDLogDebug(@"Muc %@ is already configured to be of type '%@' ('%@')...", iqNode.fromUser, mucType, [[DataLayer sharedInstance] getMucTypeOfRoom:iqNode.fromUser andAccount:_account.accountID]);
    
    //isaCloud: the guide channel comes back into the recent conversations on every join, even after being archived
    if(join && [iqNode.fromUser isEqualToString:kIsaCloudGuideRoom])
        [[DataLayer sharedInstance] addActiveBuddies:iqNode.fromUser forAccount:_account.accountID];

    if(!mucName || ![mucName length])
        mucName = @"";
    //only handle incoming name updates if they are not our own reflected changes
    if([self decrementNameChange:iqNode.fromUser])
    {
        MLContact* mucContact = [MLContact createContactFromJid:iqNode.fromUser andAccountID:_account.accountID];
        if(![mucName isEqualToString:mucContact.fullName])
        {
            DDLogInfo(@"Configuring muc %@ to use name '%@' (old value: '%@')...", iqNode.fromUser, mucName, mucContact.fullName);
            [[DataLayer sharedInstance] setFullName:mucName forContact:iqNode.fromUser andAccount:_account.accountID];
        }
    }
    
    DDLogDebug(@"Updating muc contact...");
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
        @"contact": [MLContact createContactFromJid:iqNode.fromUser andAccountID:_account.accountID]
    }];
    
    @synchronized(_stateLockObject) {
        _roomFeatures[iqNode.fromUser] = features;
        //we don't need to force saving of our new state because once this incoming iq gets counted by smacks the whole state will be saved
    }
    
    if(join)
    {
        DDLogInfo(@"Clearing muc participants table: %@", iqNode.fromUser);
        [[DataLayer sharedInstance] cleanupParticipantsListFor:iqNode.fromUser onAccountID:_account.accountID];
        
        //now try to join this room if requested
        [self sendJoinPresenceFor:iqNode.fromUser];
    }
$$

+(NSString* _Nullable) validatedNick:(NSString*) nick
{
    NSString* trimmed = [nick stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(trimmed.length == 0 || trimmed.length > 100)
        return nil;
    if([trimmed rangeOfString:@"/"].location != NSNotFound || [trimmed rangeOfString:@"@"].location != NSNotFound)
        return nil;
    if([trimmed rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound)
        return nil;
    return trimmed;
}

-(void) saveOwnNick:(NSString*) nick forMuc:(NSString*) room
{
    //both tables: ownNickNameforMuc: reads buddylist first, joins after a reconnect read muc_favorites
    [[DataLayer sharedInstance] updateOwnNickName:nick forMuc:room forAccount:_account.accountID];
    [[DataLayer sharedInstance] addMucFavorite:room forAccountID:_account.accountID andMucNick:nick];
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
        @"contact": [MLContact createContactFromJid:room andAccountID:_account.accountID]
    }];
}

-(void) changeNickOfMuc:(NSString*) room to:(NSString*) requestedNick
{
    NSString* nick = [[self class] validatedNick:requestedNick];
    if(nick == nil)
    {
        [self handleError:NSLocalizedString(@"This nickname is not valid", @"") forMuc:room withNode:nil andIsSevere:NO];
        return;
    }
    NSString* oldNick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:_account.accountID];
    if(oldNick == nil || [oldNick isEqualToString:nick])
    {
        DDLogInfo(@"Not changing nick of muc %@: unchanged or unknown (%@ --> %@)", room, oldNick, nick);
        [self callSuccessUIHandlerForMuc:room];
        return;
    }
    if([self isJoining:room] || [self isCreating:room])
    {
        [self handleError:NSLocalizedString(@"The group/channel is still being entered, please try again in a moment", @"") forMuc:room withNode:nil andIsSevere:NO];
        return;
    }
    //not entered (e.g. offline): the next join uses the new nick
    if(![self isJoined:room])
    {
        DDLogInfo(@"Muc %@ is not joined, saving nick '%@' for the next join...", room, nick);
        [self saveOwnNick:nick forMuc:room];
        [self publishNickBookmarkForMuc:room];
        [self callSuccessUIHandlerForMuc:room];
        return;
    }
    
    if(![self startNickChangeOfMuc:room from:oldNick to:nick adopt:NO])
        [self handleError:NSLocalizedString(@"The nickname is already being changed, please wait", @"") forMuc:room withNode:nil andIsSevere:NO];
}

-(void) adoptNick:(NSString*) nick forMuc:(NSString*) room
{
    NSString* oldNick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:_account.accountID];
    if(nick.length == 0 || [nick isEqualToString:oldNick])
        return;
    if(![self isJoined:room])
    {
        //not entered (or just entering): the next join uses the nick of the bookmark
        DDLogInfo(@"Adopting nick '%@' of muc %@ from its bookmark without a presence (not joined)", nick, room);
        [self saveOwnNick:nick forMuc:room];
        return;
    }
    DDLogInfo(@"Adopting nick '%@' of muc %@ from its bookmark (was '%@')...", nick, room, oldNick);
    if(![self startNickChangeOfMuc:room from:oldNick to:nick adopt:YES])
        DDLogInfo(@"Not adopting nick of muc %@: a nick change is already running", room);
}

//returns NO if a nick change of this room is running already
-(BOOL) startNickChangeOfMuc:(NSString*) room from:(NSString*) oldNick to:(NSString*) nick adopt:(BOOL) adopt
{
    NSUUID* token = [NSUUID UUID];
    @synchronized(_stateLockObject) {
        if(_changingNick[room] != nil)
            return NO;
        _changingNick[room] = @{@"nick": nick, @"oldNick": oldNick ?: @"", @"token": token, @"adopt": @(adopt)};
    }
    
    //a plain presence to the room with the new nick (no muc <x/>: this is NOT a join), with the avatar hash like all our presences
    DDLogInfo(@"Changing nick of muc %@ from '%@' to '%@'...", room, oldNick, nick);
    XMPPPresence* presence = [[XMPPPresence alloc] initWithHash:_account.capsHash];
    presence.attributes[@"to"] = [NSString stringWithFormat:@"%@/%@", room, nick];
    [_account send:presence];
    
    //no idle timer in the database on purpose (a timer left behind by a crash is what makes handleJoinTimeout assert): memory only
    __weak __typeof__(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [weakSelf nickChangeTimedOutForMuc:room withToken:token];
    });
    return YES;
}

-(void) nickChangeTimedOutForMuc:(NSString*) room withToken:(NSUUID*) token
{
    NSDictionary* pendingChange;
    @synchronized(_stateLockObject) {
        if(_changingNick[room] == nil || ![_changingNick[room][@"token"] isEqual:token])
            return;     //answered in the meantime
        pendingChange = _changingNick[room];
        [_changingNick removeObjectForKey:room];
    }
    DDLogWarn(@"Nick change of muc %@ timed out", room);
    if([pendingChange[@"adopt"] boolValue])
        return;
    [self handleError:NSLocalizedString(@"The group/channel did not answer, the nickname was not changed", @"") forMuc:room withNode:nil andIsSevere:NO];
}

-(void) publishNickBookmarkForMuc:(NSString*) room
{
    room = [room lowercaseString];
    @synchronized(_stateLockObject) {
        [_nickBookmarkPending addObject:room];
    }
    DDLogInfo(@"Fetching the bookmark item of muc %@ to update its nick...", room);
    [_account.pubsub fetchNode:@"urn:xmpp:bookmarks:1" from:_account.connectionProperties.identity.jid withItemsList:@[room] andHandler:$newHandler(MLPubSubProcessor, nickBookmarkFetched, $ID(room))];
}

-(BOOL) isNickBookmarkPendingForMuc:(NSString*) room
{
    @synchronized(_stateLockObject) {
        return [_nickBookmarkPending containsObject:[room lowercaseString]];
    }
}

-(void) finishNickBookmarkForMuc:(NSString*) room
{
    @synchronized(_stateLockObject) {
        [_nickBookmarkPending removeObject:[room lowercaseString]];
    }
}

-(void) setOwnNickOfMuc:(NSString*) room inBookmarkItem:(MLXMLNode*) item
{
    NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:_account.accountID];
    if(nick == nil)
        return;
    if(![item check:@"{urn:xmpp:bookmarks:1}conference/nick"])
        [[item findFirst:@"{urn:xmpp:bookmarks:1}conference"] addChildNode:[[MLXMLNode alloc] initWithElement:@"nick"]];
    ((MLXMLNode*)[item findFirst:@"{urn:xmpp:bookmarks:1}conference/nick"]).data = nick;
}

//returns YES if the presence was the error answer to our nick change and must not be processed any further
-(BOOL) handleNickChangePresence:(XMPPPresence*) presenceNode
{
    NSString* room = presenceNode.fromUser;
    NSDictionary* pending;
    @synchronized(_stateLockObject) {
        pending = _changingNick[room];
    }
    if(pending == nil)
        return NO;
    
    if([presenceNode check:@"/<type=error>"])
    {
        //errors come from room/new-nick
        if(presenceNode.fromResource != nil && ![presenceNode.fromResource isEqualToString:pending[@"nick"]])
            return NO;
        @synchronized(_stateLockObject) {
            [_changingNick removeObjectForKey:room];
        }
        //the known errors have their own text, the others show the text of the service
        BOOL knownError = YES;
        NSString* description = NSLocalizedString(@"Could not change nickname", @"");
        if([presenceNode check:@"/<type=error>/error/{urn:ietf:params:xml:ns:xmpp-stanzas}conflict"])
            description = NSLocalizedString(@"This nickname is already used in this group/channel", @"");
        else if([presenceNode check:@"/<type=error>/error/{urn:ietf:params:xml:ns:xmpp-stanzas}not-acceptable"])
            description = NSLocalizedString(@"This nickname is reserved or the group/channel does not allow changing it", @"");
        else if([presenceNode check:@"/<type=error>/error/{urn:ietf:params:xml:ns:xmpp-stanzas}jid-malformed"])
            description = NSLocalizedString(@"This nickname is not valid", @"");
        else
            knownError = NO;
        DDLogWarn(@"Nick change of muc %@ to '%@' failed: %@", room, pending[@"nick"], [presenceNode findFirst:@"error"]);
        //adopted nicks have no ui waiting: keep the old nick (nothing was saved) and only log
        if([pending[@"adopt"] boolValue])
            return YES;
        [self handleError:description forMuc:room withNode:(knownError ? nil : presenceNode) andIsSevere:NO];
        return YES;
    }
    
    //our own presence with the new nick (the service may have changed the nick we asked for, status 210: the nick of the service wins)
    if(![presenceNode check:@"/<type=unavailable>"] &&
        [presenceNode check:@"{http://jabber.org/protocol/muc#user}x/status<code=110>"] &&
        presenceNode.fromResource != nil && ![presenceNode.fromResource isEqualToString:pending[@"oldNick"]])
    {
        @synchronized(_stateLockObject) {
            [_changingNick removeObjectForKey:room];
        }
        DDLogInfo(@"Nick change of muc %@ confirmed: '%@' --> '%@'", room, pending[@"oldNick"], presenceNode.fromResource);
        [self saveOwnNick:presenceNode.fromResource forMuc:room];
        if(![pending[@"adopt"] boolValue])
        {
            //ORDER: database first, bookmark second (the push of our own bookmark publish must find the new nick in the database already)
            [self publishNickBookmarkForMuc:room];
            [self callSuccessUIHandlerForMuc:room];
        }
        //let the normal presence handling run: it updates the participants list
    }
    return NO;
}

//isaCloud: the service adds the avatar hash (XEP-0153) to every presence we send, but joined rooms only see it with a new presence
-(void) sendPresenceToJoinedMucs
{
    for(NSString* room in [[DataLayer sharedInstance] listMucsForAccount:_account.accountID])
    {
        NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:_account.accountID];
        if(nick == nil || ![self isJoined:room])
            continue;
        DDLogInfo(@"Sending updated presence to muc %@ as '%@'...", room, nick);
        XMPPPresence* presence = [[XMPPPresence alloc] initWithHash:_account.capsHash];
        presence.attributes[@"to"] = [NSString stringWithFormat:@"%@/%@", room, nick];
        [_account send:presence];
    }
}

-(void) sendJoinPresenceFor:(NSString*) room
{
    NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:_account.accountID];
    DDLogInfo(@"Trying to join muc '%@' with nick '%@' on account %@...", room, nick, _account);
    @synchronized(_stateLockObject) {
        //add room to "currently joining" list (and remove any present idle timer for this room)
        [[DataLayer sharedInstance] delIdleTimerWithId:_joining[room]];
        //add idle timer to display error if we did not receive the reflected join presence after 30 idle seconds
        //this will make sure the spinner ui will not spin indefinitely when adding a channel via ui
        NSNumber* timerId = [[DataLayer sharedInstance] addIdleTimerWithTimeout:@30 andHandler:$newHandler(self, handleJoinTimeout, $ID(room)) onAccountID:_account.accountID];
        _joining[room] = timerId;
        //we don't need to force saving of our new state because once this outgoing join presence gets handled by smacks the whole state will be saved
    }
    
    XMPPPresence* presence = [XMPPPresence new];
    [presence joinRoom:room withNick:nick];
    [_account send:presence];
}

$$instance_handler(handleJoinTimeout, account.mucProcessor, $$ID(xmpp*, account), $$ID(NSString*, room), $$ID(NSNumber*, timerId))
    [self handleError:[NSString stringWithFormat:NSLocalizedString(@"Could not join group/channel '%@': timeout", @""), room] forMuc:room withNode:nil andIsSevere:YES];
    
    //don't remove the muc, this could be a temporary (network induced) error, but mark it as not joining anymore
    @synchronized(_stateLockObject) {
        MLAssert([self isJoining:room] && [timerId isEqual:_joining[room]], @"Spurious idle timer firing!", (@{
            @"currentTimer": nilWrapper(_joining[room]),
            @"expectedTimer": nilWrapper(timerId),
        }));
        
        DDLogInfo(@"Aborting join of room '%@' on account %@ due to timeout", room, _account);
        [self removeRoomFromJoining:room];
    }
$$

$$instance_handler(handleMembersList, account.mucProcessor, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, type))
    DDLogInfo(@"Got %@s list from %@...", type, iqNode.fromUser);
    DDLogInfo(@"Clearing muc members table for type %@: %@", type, iqNode.fromUser);
    [[DataLayer sharedInstance] cleanupMembersListFor:iqNode.fromUser andType:type onAccountID:_account.accountID];
    [self handleMembersListUpdate:[iqNode find:@"{http://jabber.org/protocol/muc#admin}query/item@@"] forMuc:iqNode.fromUser];
    [self logMembersOfMuc:iqNode.fromUser];
$$

$$instance_handler(handleMamResponseWithLatestId, account.mucProcessor, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogWarn(@"Muc mam latest stanzaid query %@ returned error: %@", iqNode.id, [iqNode findFirst:@"error"]);
        [HelperTools postError:[NSString stringWithFormat:NSLocalizedString(@"Failed to query newest stanzaid for Group/Channel %@", @""), iqNode.fromUser] withNode:iqNode andAccount:_account andIsSevere:YES];
        [_account mamFinishedFor:iqNode.fromUser];
        return;
    }
    DDLogVerbose(@"Got latest muc stanza id to prime database with: %@", [iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"]);
    //only do this if we got a valid stanza id (not null)
    //if we did not get one we will get one when receiving the next muc message in this smacks session
    //if the smacks session times out before we get a message and someone sends us one or more messages before we had a chance to establish
    //a new smacks session, this messages will get lost because we don't know how to query the archive for this message yet
    //once we successfully receive the first mam-archived message stanza (could even be an XEP-184 ack for a sent message),
    //no more messages will get lost
    //we ignore this single message loss here, because it should be super rare and solving it would be really complicated
    if([iqNode check:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"])
        [[DataLayer sharedInstance] setLastStanzaId:[iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"] forMuc:iqNode.fromUser andAccount:_account.accountID];
    [_account mamFinishedFor:iqNode.fromUser];
$$

//isaCloud: public channels only catch up on the history window chosen in the channel details (default 7 days, 0 = whole archive)
-(NSDate* _Nullable) mamCatchupWindowStartForMuc:(NSString*) room
{
    if([[[DataLayer sharedInstance] getMucTypeOfRoom:room andAccount:_account.accountID] isEqualToString:kMucTypeChannel] == NO)
        return nil;
    NSInteger days = [[DataLayer sharedInstance] mamCatchupDaysForMuc:room andAccount:_account.accountID];
    if(days <= 0)
        return nil;
    return [NSDate dateWithTimeIntervalSinceNow:-(double)days * 24 * 60 * 60];
}

-(void) queryMamCatchupForMuc:(NSString*) room afterStanzaId:(NSString*) stanzaId
{
    XMPPIQ* mamQuery = [[XMPPIQ alloc] initWithType:kiqSetType to:room];
    NSDate* windowStart = [self mamCatchupWindowStartForMuc:room];
    MLMessage* latestMessage = windowStart ? [[DataLayer sharedInstance] lastMessageForContact:room forAccount:_account.accountID] : nil;
    //if our newest message is older than the window, skip the gap and only fetch the window
    if(windowStart && (latestMessage.timestamp == nil || [latestMessage.timestamp compare:windowStart] == NSOrderedAscending))
    {
        DDLogInfo(@"Querying muc mam:2 archive of %@ since %@ for catchup (history window)", room, windowStart);
        [mamQuery setMAMQueryAfterTimestamp:windowStart];
    }
    else
    {
        DDLogInfo(@"Querying muc mam:2 archive after stanzaid '%@' for catchup", stanzaId);
        [mamQuery setMAMQueryAfter:stanzaId];
    }
    [_account sendIq:mamQuery withHandler:$newHandler(self, handleCatchup, $BOOL(secondTry, NO))];
}

$$instance_handler(handleCatchup, account.mucProcessor, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$BOOL(secondTry))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogWarn(@"Muc mam catchup query %@ returned error: %@", iqNode.id, [iqNode findFirst:@"error"]);
        
        //handle weird XEP-0313 monkey-patching XEP-0059 behaviour (WHY THE HELL??)
        if(!secondTry && [iqNode check:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}item-not-found"])
        {
            //latestMessage can be nil, thus [latestMessage timestamp] will return nil and setMAMQueryAfterTimestamp:nil
            //will query the whole archive since dawn of time
            MLMessage* latestMessage = [[DataLayer sharedInstance] lastMessageForContact:iqNode.fromUser forAccount:_account.accountID];
            //isaCloud: never query further back than the history window of a public channel
            NSDate* start = [latestMessage timestamp];
            NSDate* windowStart = [self mamCatchupWindowStartForMuc:iqNode.fromUser];
            if(windowStart && (start == nil || [start compare:windowStart] == NSOrderedAscending))
                start = windowStart;
            DDLogInfo(@"Querying COMPLETE muc mam:2 archive at %@ after timestamp %@ for catchup", iqNode.fromUser, start);
            XMPPIQ* mamQuery = [[XMPPIQ alloc] initWithType:kiqSetType to:iqNode.fromUser];
            [mamQuery setMAMQueryAfterTimestamp:start];
            [_account sendIq:mamQuery withHandler:$newHandler(self, handleCatchup, $BOOL(secondTry, YES))];
        }
        else
        {
            [HelperTools postError:[NSString stringWithFormat:NSLocalizedString(@"Failed to query for new messages for Group/Channel (catchup) %@", @""), iqNode.fromUser] withNode:iqNode andAccount:_account andIsSevere:YES];
            [_account mamFinishedFor:iqNode.fromUser];
        }
        return;
    }
    //we need to check for the rsm/last element because of a weird ejabberd bug sending complete=false, but no rsm last element
    if(![[iqNode findFirst:@"{urn:xmpp:mam:2}fin@complete|bool"] boolValue] && [iqNode check:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"])
    {
        DDLogVerbose(@"Paging through muc mam catchup results at %@ with after: %@", iqNode.fromUser, [iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"]);
        //do RSM forward paging
        XMPPIQ* pageQuery = [[XMPPIQ alloc] initWithType:kiqSetType to:iqNode.fromUser];
        [pageQuery setMAMQueryAfter:[iqNode findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/last#"]];
        [_account sendIq:pageQuery withHandler:$newHandler(self, handleCatchup, $BOOL(secondTry, NO))];
    }
    else
    {
        DDLogVerbose(@"Muc mam catchup of %@ finished", iqNode.fromUser);
        [_account mamFinishedFor:iqNode.fromUser];
    }
$$

-(void) fetchAvatarForRoom:(NSString*) room
{
    XMPPIQ* vcardQuery = [[XMPPIQ alloc] initWithType:kiqGetType to:room];
    [vcardQuery setVcardQuery];
    [_account sendIq:vcardQuery withHandler:$newHandler(self, handleVcardResponse)];
}

$$instance_handler(handleVcardResponse, account.mucProcessor, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode))
    BOOL deleteAvatar = ![iqNode check:@"{vcard-temp}vCard/PHOTO/BINVAL#"];
    
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Failed to retrieve avatar of muc '%@', error: %@", iqNode.fromUser, [iqNode findFirst:@"error"]);
        deleteAvatar = YES;
    }
    
    if(deleteAvatar)
    {
        [[MLImageManager sharedInstance] setIconForContact:[MLContact createContactFromJid:iqNode.fromUser andAccountID:_account.accountID] WithData:nil];
        [[DataLayer sharedInstance] setAvatarHash:@"" forContact:iqNode.fromUser andAccount:_account.accountID];
        //delete cache to make sure the image will be regenerated
        [[MLImageManager sharedInstance] purgeCacheForContact:iqNode.fromUser andAccount:_account.accountID];
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
            @"contact": [MLContact createContactFromJid:iqNode.fromUser andAccountID:_account.accountID]
        }];
        DDLogInfo(@"Avatar of muc '%@' deleted successfully", iqNode.fromUser);
    }
    else
    {
        //this should be small enough to not crash the appex when loading the image from file later on but large enough to have excellent quality
        NSData* imageData = [iqNode findFirst:@"{vcard-temp}vCard/PHOTO/BINVAL#|base64"];
        if([HelperTools isAppExtension] && imageData.length > 128 * 1024)
        {
            DDLogWarn(@"Not processing avatar image data of muc '%@' because it is too big to be handled in appex (%lu bytes), rescheduling it to be fetched in mainapp", iqNode.fromUser, (unsigned long)imageData.length);
            [_account addReconnectionHandler:$newHandler(self, fetchAvatarAgain, $ID(jid, iqNode.fromUser))];
            return;
        }
        
        //this will consume a large portion of ram because it will be represented as uncomressed bitmap
        UIImage* image = [UIImage imageWithData:imageData];
        NSString* avatarHash = [HelperTools hexadecimalString:[HelperTools sha1:imageData]];
        //this upper limit is roughly 1.4MiB memory (600x600 with 4 byte per pixel)
        if(![HelperTools isAppExtension] || image.size.width * image.size.height < 600 * 600)
        {
            NSData* imageData = [HelperTools resizeAvatarImage:image withCircularMask:YES toMaxBase64Size:256000];
            [[MLImageManager sharedInstance] setIconForContact:[MLContact createContactFromJid:iqNode.fromUser andAccountID:_account.accountID] WithData:imageData];
            [[DataLayer sharedInstance] setAvatarHash:avatarHash forContact:iqNode.fromUser andAccount:_account.accountID];
            //delete cache to make sure the image will be regenerated
            [[MLImageManager sharedInstance] purgeCacheForContact:iqNode.fromUser andAccount:_account.accountID];
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
                @"contact": [MLContact createContactFromJid:iqNode.fromUser andAccountID:_account.accountID]
            }];
            DDLogInfo(@"Avatar of muc '%@' fetched and updated successfully", iqNode.fromUser);
        }
        else
        {
            DDLogWarn(@"Not loading avatar image of muc '%@' because it is too big to be processed in appex (%lux%lu pixels), rescheduling it to be fetched in mainapp", iqNode.fromUser, (unsigned long)image.size.width, (unsigned long)image.size.height);
            [_account addReconnectionHandler:$newHandler(self, fetchAvatarAgain, $ID(jid, iqNode.fromUser))];
        }
    }
$$

//this handler will simply retry the vcard fetch attempt if in mainapp
$$instance_handler(fetchAvatarAgain, account.mucProcessor, $$ID(xmpp*, account), $$ID(NSString*, jid))
    if([HelperTools isAppExtension])
    {
        DDLogWarn(@"Not loading avatar image of '%@' because we are still in appex, rescheduling it again!", jid);
        [_account addReconnectionHandler:$newHandler(self, fetchAvatarAgain, $ID(jid))];
    }
    else
        [self fetchAvatarForRoom:jid];
$$

-(void) handleError:(NSString*) description forMuc:(NSString*) room withNode:(XMPPStanza*) node andIsSevere:(BOOL) isSevere
{
    monal_id_block_t uiHandler = [self getUIHandlerForMuc:room];
    //call ui handler if registered for this room
    if(uiHandler)
    {
        //remove handler (it will only be called once)
        [self removeUIHandlerForMuc:room];
        
        //prepare data        
        NSString* message = description;
        if(node != nil)
            message = [HelperTools extractXMPPError:node withDescription:description];
        NSDictionary* data = @{
            @"success": @NO,
            @"muc": room,
            @"account": _account,
            @"errorMessage": message
        };
        
        DDLogInfo(@"Calling UI error handler with %@", data);
        dispatch_async(dispatch_get_main_queue(), ^{
            uiHandler(data);
        });
    }
    //otherwise call the general error handler
    else
        [HelperTools postError:description withNode:node andAccount:_account andIsSevere:isSevere];
}

-(void) callSuccessUIHandlerForMuc:(NSString*) room withCallback:(monal_void_block_t) callback
{
    monal_id_block_t uiHandler = [self getUIHandlerForMuc:room];
    if(uiHandler)
    {
        //remove handler (it will only be called once)
        [self removeUIHandlerForMuc:room];
        
        DDLogInfo(@"Calling UI handler for muc %@...", room);
        dispatch_async(dispatch_get_main_queue(), ^{
            if(callback != nil)
                uiHandler(@{
                    @"success": @YES,
                    @"muc": room,
                    @"account": self->_account,
                    @"callback": callback,
                });
            else
                uiHandler(@{
                    @"success": @YES,
                    @"muc": room,
                    @"account": self->_account,
                });
        });
    }
}

-(void) callSuccessUIHandlerForMuc:(NSString*) room
{
    return [self callSuccessUIHandlerForMuc:room withCallback:nil];
}

-(void) updateBookmarks
{
    DDLogVerbose(@"Updating bookmarks on account %@", _account);
    [_account.pubsub fetchNode:@"urn:xmpp:bookmarks:1" from:_account.connectionProperties.identity.jid withItemsList:nil andHandler:$newHandler(MLPubSubProcessor, handleBookmarks2FetchResult)];
}

-(BOOL) checkIfStillBookmarked:(NSString*) room
{
    room = [room lowercaseString];
    for(NSString* entry in [[DataLayer sharedInstance] listMucsForAccount:_account.accountID])
        if([room isEqualToString:entry])
            return YES;
    return NO;
}

-(NSSet*) getRoomFeaturesForMuc:(NSString*) room
{
    return _roomFeatures[room];
}

-(void) deleteMuc:(NSString*) room withBookmarksUpdate:(BOOL) updateBookmarks keepBuddylistEntry:(BOOL) keepBuddylistEntry
{
    DDLogInfo(@"Deleting muc %@ on account %@...", room, _account);
    
    //delete muc from favorites table and update bookmarks if requested
    [[DataLayer sharedInstance] deleteMuc:room forAccountID:_account.accountID];
    if(updateBookmarks)
        [self updateBookmarks];
    
    //update buddylist (e.g. contact list) if requested
    MLContact* contact = [MLContact createContactFromJid:room andAccountID:_account.accountID];
    [contact removeShareInteractions];
    if(keepBuddylistEntry)
    {
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:_account userInfo:@{
            @"contact": contact
        }];
    }
    else
    {
        [[DataLayer sharedInstance] removeBuddy:room forAccount:_account.accountID];
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRemoved object:_account userInfo:@{
            @"contact": contact
        }];
    }
}

-(NSString*) calculateNickForMuc:(NSString*) room
{
    NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:room forAccount:_account.accountID];
    //use the account display name as nick, if nothing can be found in buddylist and muc_favorites db tables
    if(!nick)
    {
        nick = [MLContact ownDisplayNameForAccount:_account];
        DDLogInfo(@"Using default nick '%@' for room %@ on account %@", nick, room, _account);
    }
    return nick;
}

-(void) removeRoomFromCreating:(NSString*) room
{
    @synchronized(_stateLockObject) {
        DDLogVerbose(@"Removing from _creating[%@]: %@", room, _creating[room]);
        [[DataLayer sharedInstance] delIdleTimerWithId:_creating[room]];
        [_creating removeObjectForKey:room];
    }
}

-(void) removeRoomFromJoining:(NSString*) room
{
    @synchronized(_stateLockObject) {
        DDLogVerbose(@"Removing from _joining[%@]: %@", room, _joining[room]);
        [[DataLayer sharedInstance] delIdleTimerWithId:_joining[room]];
        [_joining removeObjectForKey:room];
    }
}

-(void) logMembersOfMuc:(NSString*) jid
{
    if([[[DataLayer sharedInstance] getMucTypeOfRoom:jid andAccount:_account.accountID] isEqualToString:kMucTypeGroup])
        DDLogInfo(@"Currently recorded members and participants of group %@: %@", jid, [[DataLayer sharedInstance] getMembersAndParticipantsOfMuc:jid forAccountID:_account.accountID]);
    else
    {
//these lists can potentially get really long for public channels --> restrict logging them to alpha builds
#ifdef IS_ALPHA
    DDLogInfo(@"Currently recorded members and participants of channel %@: %@", jid, [[DataLayer sharedInstance] getMembersAndParticipantsOfMuc:jid forAccountID:_account.accountID]);
#endif
    }
}

-(NSString*) generateSpeakableGroupNode
{
    NSArray* charLists = @[
        @"bcdfghjklmnpqrstvwxyz",
        @"aeiou",
    ];
    NSMutableString* retval = [NSMutableString new];
    int charTypeBegin = arc4random() % charLists.count;
    for(int i=0; i<10; i++)
    {
        NSString* selectedCharList = charLists[(i + charTypeBegin) % charLists.count];
        [retval appendString:[selectedCharList substringWithRange:NSMakeRange(arc4random() % selectedCharList.length, 1)]];
    }
    return retval;
}

@end
