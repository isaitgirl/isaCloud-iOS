//
//  DataLayer.h
//  SworIM
//
//  Created by Anurodh Pokharel on 3/28/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/XMPPPresence.h>
#import <monalxmpp/MLMessage.h>
#import <monalxmpp/MLContact.h>
#import <monalxmpp/MLPromise.h>
#import <monalxmpp/MLContactSoftwareVersionInfo.h>

NS_ASSUME_NONNULL_BEGIN

//isaCloud: a room's occupants can have hats (XEP-0317); posted on the main thread when the hats of an occupant change, userInfo has "room"
extern NSString* const kMonalMucHatsUpdated;
//isaCloud: an avatar of a person who is not our contact was fetched or removed (userInfo: owner, see getRemoteAvatarInfoForOwner:)
extern NSString* const kMonalRemoteAvatarUpdated;

@interface DataLayer : NSObject

extern NSString* const kAccountID;
extern NSString* const kAccountState;
extern NSString* const kDomain;
extern NSString* const kEnabled;
extern NSString* const kNeedsPasswordMigration;
extern NSString* const kPlainActivated;

extern NSString* const kServer;
extern NSString* const kPort;
extern NSString* const kResource;
extern NSString* const kDirectTLS;
extern NSString* const kRosterName;

extern NSString* const kUsername;

extern NSString* const kMessageTypeStatus;
extern NSString* const kMessageTypeMessageDraft;
extern NSString* const kMessageTypeText;
extern NSString* const kMessageTypeGeo;
extern NSString* const kMessageTypeUrl;
extern NSString* const kMessageTypeFiletransfer;

+(DataLayer*) sharedInstance;
-(NSString* _Nullable) exportDB;
-(void) clearAvatarHashCache;
-(void) createTransaction:(monal_void_block_t) block;
-(void) addEndTransactionTrigger:(monal_void_block_t) trigger withLocation:(NSString*) location;
-(BOOL) vacuum;

//Roster
-(NSString *) getRosterVersionForAccount:(NSNumber*) accountID;
-(void) setRosterVersion:(NSString *) version forAccount: (NSNumber*) accountID;

// Buddy Commands
-(BOOL) addContact:(NSString*) contact  forAccount:(NSNumber*) accountID nickname:(NSString* _Nullable) nickName;
-(void) removeBuddy:(NSString*) buddy forAccount:(NSNumber*) accountID;
-(BOOL) clearBuddies:(NSNumber*) accountID;
-(NSDictionary* _Nullable) contactDictionaryForUsername:(NSString*) username forAccount: (NSNumber*) accountID;

/**
 should be called when a new session needs to be established
 */
-(BOOL) resetContactsForAccount:(NSNumber*) accountID;

-(NSMutableArray<MLContact*>*) searchContactsWithString:(NSString*) search;

-(NSArray<MLContact*>*) contactList;
-(NSArray<MLContact*>*) contactListWithJid:(NSString*) jid;
-(NSArray<MLContact*>*) possibleGroupMembersForAccount:(NSNumber*) accountID;
-(NSArray<NSString*>*) resourcesForContact:(MLContact* _Nonnull)contact ;
-(MLContactSoftwareVersionInfo* _Nullable) getSoftwareVersionInfoForContact:(NSString*)contact resource:(NSString*)resource andAccount:(NSNumber*)account;
-(void) setSoftwareVersionInfoForContact:(NSString*)contact
                                resource:(NSString*)resource
                              andAccount:(NSNumber*)account
                                withSoftwareInfo:(MLContactSoftwareVersionInfo*) newSoftwareInfo;

#pragma mark Ver string and Capabilities

-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user onAccountID:(NSNumber*) accountID;
-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user andResource:(NSString*) resource onAccountID:(NSNumber*) accountID;
-(NSString*) getVerForUser:(NSString*) user andResource:(NSString*) resource onAccountID:(NSNumber*) accountID;
-(void) setVer:(NSString*) ver forUser:(NSString*) user andResource:(NSString*) resource onAccountID:(NSNumber*) accountID;
-(NSSet* _Nullable) getCapsforVer:(NSString*) ver onAccountID:(NSNumber*) accountID;
-(void) setCaps:(NSSet*) caps forVer:(NSString*) ver onAccountID:(NSNumber*) accountID;

#pragma mark  presence functions
-(void) setResourceOnline:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountID;
-(void) setOnlineBuddy:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountID;
-(void) setOfflineBuddy:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountID;

-(void) setBuddyStatus:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountID;
-(NSString*) buddyStatus:(NSString*) buddy forAccount:(NSNumber*) accountID;

-(void) setBuddyState:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountID;
-(NSString*) buddyState:(NSString*) buddy forAccount:(NSNumber*) accountID;

-(BOOL) hasContactRequestForContact:(MLContact*) contact;
-(NSMutableArray*) allContactRequests;
-(void) addContactRequest:(MLContact *) requestor;
-(void) deleteContactRequest:(MLContact *) requestor; 

#pragma mark Contact info

-(void) setFullName:(NSString*) fullName forContact:(NSString*) contact andAccount:(NSNumber*) accountID;

-(void) setAvatarHash:(NSString*) hash forContact:(NSString*) contact andAccount:(NSNumber*) accountID;
-(NSString*) getAvatarHashForContact:(NSString*) buddy andAccount:(NSNumber*) accountID;

-(BOOL) saveMessageDraft:(NSString*) buddy forAccount:(NSNumber*) accountID withComment:(NSString*) comment;
-(NSString* _Nullable) loadMessageDraft:(NSString*) buddy forAccount:(NSNumber*) accountID;
-(NSDictionary* _Nullable) getDraftMessageDictionaryForJid:(NSString*) jid onAccount:(NSNumber*) accountID;

#pragma mark - MUC

-(BOOL) initMuc:(NSString*) room forAccountID:(NSNumber*) accountID andMucNick:(NSString* _Nullable) mucNick;
-(void) cleanupParticipantsListFor:(NSString*) room onAccountID:(NSNumber*) accountID;
-(void) cleanupMembersListFor:(NSString*) room andType:(NSString*) type onAccountID:(NSNumber*) accountID;
-(void) addMember:(NSDictionary*) member toMuc:(NSString*) room forAccountID:(NSNumber*) accountID;
-(void) removeMember:(NSDictionary*) member fromMuc:(NSString*) room forAccountID:(NSNumber*) accountID;
-(void) addParticipant:(NSDictionary*) participant toMuc:(NSString*) room forAccountID:(NSNumber*) accountID;
-(void) removeParticipant:(NSDictionary*) participant fromMuc:(NSString*) room forAccountID:(NSNumber*) accountID;
-(void) addVoiceRequestBy:(NSString*) jid occupyingNick:(NSString* _Nullable) nick inRoom:(MLContact*) contact;
-(void) removeVoiceRequestBy:(NSString*) jid inRoom:(MLContact*) contact;
-(NSArray*) getVoiceRequestsForRoom:(MLContact*) contact;
-(NSDictionary* _Nullable) getParticipantForNick:(NSString*) nick inRoom:(NSString*) room forAccountID:(NSNumber*) accountID;
-(NSDictionary* _Nullable) getParticipantForOccupant:(NSString*) occupant inRoom:(NSString*) room forAccountID:(NSNumber*) accountID;
//isaCloud: hats of an occupant (dictionaries with "uri" and "title"), saved in the database and replaced by every presence of the occupant
-(void) setMucHats:(NSArray<NSDictionary<NSString*, NSString*>*>*) hats forRoom:(NSString*) room nick:(NSString*) nick forAccountID:(NSNumber*) accountID;
-(NSArray<NSDictionary<NSString*, NSString*>*>*) getMucHatsForRoom:(NSString*) room nick:(NSString*) nick forAccountID:(NSNumber*) accountID;
//isaCloud: avatars of people we have no PEP avatar from. "owner" is the bare jid (members of groups) or room|occupant-id (participants of channels).
//Returns @{hash, fetched_hash, failed_hash, failed_at, fail_count} (strings as NSNull when unset) or nil when the owner is unknown
-(NSDictionary* _Nullable) getRemoteAvatarInfoForOwner:(NSString*) owner forAccountID:(NSNumber*) accountID;
//saves the hash seen in a presence (empty string: no avatar), returns YES if it differs from the one saved before
-(BOOL) noteRemoteAvatarHash:(NSString*) hash forOwner:(NSString*) owner forAccountID:(NSNumber*) accountID;
-(void) setRemoteAvatarFetchedHash:(NSString* _Nullable) hash forOwner:(NSString*) owner forAccountID:(NSNumber*) accountID;
//remembers a failed attempt for this hash and returns how many attempts failed in a row
-(NSInteger) setRemoteAvatarFailedForHash:(NSString*) hash forOwner:(NSString*) owner forAccountID:(NSNumber*) accountID;
-(NSArray<NSDictionary<NSString*, id>*>*) getMembersAndParticipantsOfMuc:(NSString*) room forAccountID:(NSNumber*) accountID;
-(NSString* _Nullable) getOwnAffiliationInGroupOrChannel:(MLContact*) contact;
-(NSString* _Nullable) getOwnRoleInGroupOrChannel:(MLContact*) contact;
-(void) addMucFavorite:(NSString*) room forAccountID:(NSNumber*) accountID andMucNick:(NSString* _Nullable) mucNick;
-(NSString*) lastStanzaIdForMuc:(NSString* _Nonnull) room andAccount:(NSNumber* _Nonnull) accountID;
-(void) setLastStanzaId:(NSString*) lastStanzaId forMuc:(NSString* _Nonnull) room andAccount:(NSNumber* _Nonnull) accountID;
-(BOOL) isBuddyMuc:(NSString*) buddy forAccount:(NSNumber*) accountID;

-(NSString* _Nullable) ownNickNameforMuc:(NSString*) room forAccount:(NSNumber*) accountID;
-(BOOL) updateOwnNickName:(NSString*) nick forMuc:(NSString*) room forAccount:(NSNumber*) accountID;

-(BOOL) updateOwnOccupantID:(NSString* _Nullable) occupantID forMuc:(NSString*) room onAccountID:(NSNumber*) accountID;
-(NSString* _Nullable) getOwnOccupantIdForMuc:(NSString*) room onAccountID:(NSNumber*) accountID;

-(BOOL) updateMucSubject:(NSString*) subject forAccount:(NSNumber*) accountID andRoom:(NSString*) room;
-(NSString*) mucSubjectforAccount:(NSNumber*) accountID andRoom:(NSString*) room;

-(NSSet*) listMucsForAccount:(NSNumber*) accountID;
-(BOOL) deleteMuc:(NSString*) room forAccountID:(NSNumber*) accountID;

-(void) updateMucTypeTo:(NSString*) type forRoom:(NSString*) room andAccount:(NSNumber*) accountID;
-(NSString*) getMucTypeOfRoom:(NSString*) room andAccount:(NSNumber*) accountID;

//isaCloud: days of MAM history to catch up on connect for public channels (0 = whole archive, default 7)
-(NSInteger) mamCatchupDaysForMuc:(NSString*) room andAccount:(NSNumber*) accountID;
-(void) setMamCatchupDays:(NSInteger) days forMuc:(NSString*) room andAccount:(NSNumber*) accountID;

/**
 Calls with YES if contact  has already been added to the database for this account
 */
-(BOOL) isContactInList:(NSString*) buddy forAccount:(NSNumber*) accountID;

#pragma mark - account commands
-(NSNumber*) accountCnts;
-(NSArray*) accountList;
-(NSNumber*) enabledAccountCnts;
-(NSArray*) enabledAccountList;
-(BOOL) isAccountEnabled:(NSNumber*) accountID;
-(BOOL) doesAccountExistUser:(NSString*) user andDomain:(NSString *) domain;
-(NSNumber* _Nullable) accountIDForUser:(NSString*) user andDomain:(NSString *) domain;

-(NSMutableDictionary* _Nullable) detailsForAccount:(NSNumber*) accountID;

-(BOOL) updateAccounWithDictionary:(NSDictionary *) dictionary;
-(NSNumber* _Nullable) addAccountWithDictionary:(NSDictionary *) dictionary;


-(BOOL) removeAccount:(NSNumber*) accountID;

/**
 password migration
 */
-(BOOL) disableAccountForPasswordMigration:(NSNumber*) accountID;
-(NSArray*) accountListNeedingPasswordMigration;

-(BOOL) isPlainActivatedForAccount:(NSNumber*) accountID;
-(BOOL) deactivatePlainForAccount:(NSNumber*) accountID;

-(BOOL) isPasswordAutogeneratedForAccount:(NSNumber*) accountID;
-(BOOL) setPasswordAutogenerated:(BOOL) passwordAutogenerated forAccount:(NSNumber*) accountID;

-(NSMutableDictionary* _Nullable) readStateForAccount:(NSNumber*) accountID;
-(void) persistState:(NSDictionary*) state forAccount:(NSNumber*) accountID;

#pragma mark - message Commands
/**
 returns messages with the provided local id number
 */
-(NSNumber*) getAutodecrementHistoryId;
-(NSNumber*) getNewestHistoryEntryIdForAccount:(NSNumber*) accountID withMuc:(BOOL) muc;

-(NSNumber* _Nullable) hasMessageForStanzaId:(NSString*) stanzaId orMessageID:(NSString*) messageId withInboundDir:(BOOL) inbound occupantId:(NSString* _Nullable) occupantId andJid:(NSString*) jid onAccount:(NSNumber*) accountID;

/*
 adds a specified message to the database
 */
-(NSNumber*) addMessageToChatBuddy:(NSString*) buddyName withInboundDir:(BOOL) inbound forAccount:(NSNumber*) accountID withBody:(NSString*) message actuallyfrom:(NSString*) actualfrom occupantId:(NSString* _Nullable) occupantId participantJid:(NSString*_Nullable) participantJid sent:(BOOL) sent unread:(BOOL) unread messageId:(NSString*) messageid serverMessageId:(NSString*) stanzaid messageType:(NSString*) messageType andOverrideDate:(NSDate*) messageDate encrypted:(BOOL) encrypted displayMarkerWanted:(BOOL) displayMarkerWanted usingHistoryId:(NSNumber* _Nullable) historyId checkForDuplicates:(BOOL) checkForDuplicates;

/*
 Marks a message as sent. When the server acked it
 */
-(void) setMessageId:(NSString*_Nonnull) messageid andJid:(NSString*) jid sent:(BOOL) sent;

/**
 Marked when the client on the other end replies with a recived message
 */
-(void) setMessageId:( NSString* _Nonnull ) messageid andJid:(NSString*) jid received:(BOOL) received;
/**
 if the server replies with an error for a message, store it
 */
-(void) setMessageId:(NSString* _Nonnull) messageid andJid:(NSString*) jid errorType:(NSString *_Nonnull) errorType errorReason:(NSString *_Nonnull)errorReason;
-(void) clearErrorOfMessageId:(NSString* _Nonnull) messageid;

/**
 sets a preview info for a specified message
 */
-(void) setMessageId:(NSString*_Nonnull) messageid previewText:(NSString *) text andPreviewImage:(NSString *) image;
-(void) setMessageId:(NSString*) messageid stanzaId:(NSString *) stanzaId;
-(void) setMessageHistoryId:(NSNumber*) historyId messageType:(NSString*) messageType;

-(NSDictionary*) getFiletransferInfoForHistoryId:(NSNumber*) historyId;
//isaCloud: makes sure the filetransfer_info row of a filetransfer message exists (an empty one, mime type and size are filled in later)
-(void) ensureFiletransferInfoForHistoryId:(NSNumber*) historyId;
-(void) setFiletransferInfoForHistoryId:(NSNumber*) historyId withMimeType:(NSString*) mimeType andSize:(NSNumber*) size;

-(void) clearMessages:(NSNumber*) accountID;
-(void) clearMessagesWithBuddy:(NSString*) buddy onAccount:(NSNumber*) accountID;
-(NSNumber*) autoDeleteMessagesAfterInterval:(NSTimeInterval)interval;
-(void) retractMessageHistory:(NSNumber *) messageNo;
-(void) deleteMessageHistoryLocally:(NSNumber*) messageNo;
-(void) updateMessageHistory:(NSNumber*) messageNo withText:(NSString*) newText;
-(NSNumber* _Nullable) getLMCHistoryIDForMessageId:(NSString*) messageid from:(NSString*) from occupantId:(NSString* _Nullable) occupantId participantJid:(NSString* _Nullable) participantJid andAccount:(NSNumber*) accountID;
-(NSNumber* _Nullable) getRetractionHistoryIDForMessageId:(NSString*) messageid from:(NSString*) from participantJid:(NSString* _Nullable) participantJid occupantId:(NSString* _Nullable) occupantId andAccount:(NSNumber*) accountID;
-(NSNumber* _Nullable) getRetractionHistoryIDForModeratedStanzaId:(NSString*) stanzaId from:(NSString*) from andAccount:(NSNumber*) accountID;

-(NSNumber* _Nullable) getReactionHistoryIDForMessageIdOrStanzaId:(NSString*) someId inChat:(MLContact*) contact;
-(void) setReactions:(NSOrderedSet*) reactions fromJid:(NSString* _Nullable) jid orOccupantId:(NSString* _Nullable) occupantId forHistoryId:(NSNumber*) historyId withDate:(NSDate*) date andActualFrom:(NSString* _Nullable) actualFrom;
-(NSArray<MLReactionsEntry*>*) getReactionsForHistoryId:(NSNumber*) historyId;

-(NSDate* _Nullable) returnTimestampForQuote:(NSNumber*) historyID;
-(BOOL) checkLMCEligible:(NSNumber*) historyID encrypted:(BOOL) encrypted historyBaseID:(NSNumber* _Nullable) historyBaseID;

#pragma mark - message history

-(NSNumber*) lastMessageHistoryIdForContact:(NSString*) buddy forAccount:(NSNumber*) accountID;
-(NSMutableArray<MLMessage*>*) messagesForContact:(NSString*) buddy forAccount:(NSNumber*) accountID beforeMsgHistoryID:(NSNumber* _Nullable) msgHistoryID;
-(NSMutableArray<MLMessage*>*) messagesForContact:(NSString*) buddy forAccount:(NSNumber*) accountID;
//isaCloud: the messages of a chat from a few before the message `historyId` (context) up to, not including, `beforeHistoryId`, oldest first; used to open a chat at a message
//found by the search. Returns nil, if there are more than `limit` of them (the chat view would be too heavy)
-(NSMutableArray<MLMessage*>* _Nullable) messagesForContact:(NSString*) buddy forAccount:(NSNumber*) accountID aroundMsgHistoryID:(NSNumber*) historyId beforeMsgHistoryID:(NSNumber*) beforeHistoryId limit:(NSUInteger) limit;
-(NSDictionary*) messageDataForHistoryID:(NSNumber*) historyID;
//isaCloud: like messageDataForHistoryID:, but nil instead of an assertion if the message does not exist (anymore), e.g. after removing its account
-(NSDictionary* _Nullable) optionalMessageDataForHistoryID:(NSNumber*) historyID;


-(MLMessage*) lastMessageForContact:(NSString*) contact forAccount:(NSNumber*) accountID;
-(NSString*) lastStanzaIdForAccount:(NSNumber*) accountID;
-(void) setLastStanzaId:(NSString*) lastStanzaId forAccount:(NSNumber*) accountID;

-(NSArray<MLMessage*>*) markMessagesAsReadForBuddy:(NSString*) buddy andAccount:(NSNumber*) accountID tillStanzaId:(NSString* _Nullable) stanzaId wasOutgoing:(BOOL) outgoing;

-(NSNumber*) addMessageHistoryTo:(NSString*) to forAccount:(NSNumber*) accountID withMessage:(NSString*) message actuallyFrom:(NSString*) actualfrom withOccupantId:(NSString* _Nullable) occupantId andId:(NSString*) messageId encrypted:(BOOL) encrypted messageType:(NSString*) messageType mimeType:(NSString* _Nullable) mimeType size:(NSNumber* _Nullable) size;

#pragma mark active contacts
-(NSMutableArray<MLContact*>*) activeContactsWithPinned:(BOOL) pinned;
-(NSArray<MLContact*>*) activeContactDict;
-(void) removeActiveBuddy:(NSString*) buddyname forAccount:(NSNumber*) accountID;
-(void) addActiveBuddies:(NSString*) buddyname forAccount:(NSNumber*) accountID;
-(BOOL) isActiveBuddy:(NSString*) buddyname forAccount:(NSNumber*) accountID;
-(BOOL) updateActiveBuddy:(NSString*) buddyname setTime:(NSString*)timestamp forAccount:(NSNumber*) accountID;



#pragma mark count unread
-(NSNumber*) countUserUnreadMessages:(NSString* _Nullable) buddy forAccount:(NSNumber* _Nullable) accountID;
//isaCloud: YES if one of the newest unread text messages of this chat contains one of the given names (case insensitive)
-(BOOL) hasUnreadMentionInMuc:(NSString*) buddy forAccount:(NSNumber*) accountID withNames:(NSArray<NSString*>*) names;
-(NSNumber*) countUnreadMessages;

-(void) muteContact:(MLContact*) contact;
-(void) unMuteContact:(MLContact*) contact;
-(BOOL) isMutedJid:(NSString*) jid onAccount:(NSNumber*) accountID;

-(void) setMucAlertOnMentionOnly:(NSString*) jid onAccount:(NSNumber*) accountID;
-(void) setMucAlertOnAll:(NSString*) jid onAccount:(NSNumber*) accountID;
-(BOOL) isMucAlertOnMentionOnly:(NSString*) jid onAccount:(NSNumber*) accountID;

-(void) blockJid:(NSString*) jid withAccountID:(NSNumber*) accountID;
-(void) unBlockJid:(NSString*) jid withAccountID:(NSNumber*) accountID;
-(BOOL) isBlockedContact:(MLContact*) contact;
-(void) updateLocalBlocklistCache:(NSSet<NSString*>*) blockedJids forAccountID:(NSNumber*) accountID;
-(NSArray<NSString*>*) blockedJidsForAccount:(NSNumber*) accountID;

-(BOOL) isPinnedChat:(NSNumber*) accountID andBuddyJid:(NSString*) buddyJid;
-(void) pinChat:(NSNumber*) accountID andBuddyJid:(NSString*) buddyJid;
-(void) unPinChat:(NSNumber*) accountID andBuddyJid:(NSString*) buddyJid;

-(BOOL) shouldEncryptForJid:(NSString *) jid andAccountID:(NSNumber*) account;
-(void) encryptForJid:(NSString*) jid andAccountID:(NSNumber*) accountID;
-(void) disableEncryptForJid:(NSString*) jid andAccountID:(NSNumber*) accountID;

-(NSMutableArray<MLFiletransferInfo*>*) allAttachmentsFromContact:(NSString*) contact forAccount:(NSNumber*) accountID;

-(NSDate* _Nullable) lastInteractionOfJid:(NSString* _Nonnull) jid forAccountID:(NSNumber* _Nonnull) accountID;
-(NSDate* _Nullable) lastInteractionOfJid:(NSString* _Nonnull) jid andResource:(NSString* _Nonnull) resource forAccountID:(NSNumber* _Nonnull) accountID;
-(void) setLastInteraction:(NSDate*) lastInteractionTime forJid:(NSString* _Nonnull) jid andResource:(NSString*) resource onAccountID:(NSNumber* _Nonnull) accountID;
-(void) resetGlobalLastInteractionForJid:(NSString* _Nonnull) jid onAccountID:(NSNumber* _Nonnull) accountID;

-(NSDictionary *) getSubscriptionForContact:(NSString*) contact andAccount:(NSNumber*) accountID;
-(void) setSubscription:(NSString *)sub andAsk:(NSString*) ask forContact:(NSString*) contact andAccount:(NSNumber*) accountID;
-(void) setGroups:(NSSet*) groups forContact:(NSString*) contact inAccount:(NSNumber*) accountID;

#pragma mark History Message Search
/*
 search message by keyword in message, buddy_name, messageType.
 */
//isaCloud: full text search in the messages (every word a prefix, accents and case do not matter), newest first; see MLMessageSearch
-(NSArray<NSNumber*>*) searchMessageHistoryIdsForQuery:(NSString*) query limit:(NSUInteger) limit offset:(NSUInteger) offset;

-(NSArray* _Nullable) searchResultOfHistoryMessageWithKeyWords:(NSString* _Nonnull) keyword
                                             accountID:(NSNumber*  _Nonnull) accountID;

/*
 search message by keyword in message, buddy_name, messageType.
 */
-(NSArray*) searchResultOfHistoryMessageWithKeyWords:(NSString*) keyword betweenContact:(MLContact* _Nonnull) contact;

-(void) invalidateAllAccountStates;

-(NSString*) lastUsedPushServerForAccount:(NSNumber*) accountID;
-(void) updateUsedPushServer:(NSString*) pushServer forAccount:(NSNumber*) accountID;
-(void) markReachedMamArchiveTopForContact:(MLContact*) contact;
-(void) activateExplicitOmemoTrustForContact:(MLContact*) contact;



-(void) deleteDelayedMessageStanzasForAccount:(NSNumber*) accountID;
-(void) addDelayedMessageStanza:(MLXMLNode*) stanza forArchiveJid:(NSString*) archiveJid andAccountID:(NSNumber*) accountID;
-(MLXMLNode* _Nullable) getNextDelayedMessageStanzaForArchiveJid:(NSString*) archiveJid andAccountID:(NSNumber*) accountID;

-(void) addShareSheetPayload:(NSDictionary*) payload;
-(NSArray*) getShareSheetPayload;
-(void) deleteShareSheetPayloadWithId:(NSNumber*) payloadId;
//isaCloud: removes every share sheet item still waiting to be sent (debug screen); returns how many were removed
-(NSUInteger) clearShareSheetOutbox;

-(NSNumber*) addIdleTimerWithTimeout:(NSNumber*) timeout andHandler:(MLHandler*) handler onAccountID:(NSNumber*) accountID;
-(void) delIdleTimerWithId:(NSNumber* _Nullable) timerId;
-(void) cleanupIdleTimerOnAccountID:(NSNumber*) accountID;
-(BOOL) decrementIdleTimersForAccount:(xmpp*) account;

-(void) addPromise:(MLPromise*) promise;
-(void) removePromise:(MLPromise*) promise;
-(void) removeAllPromises;
-(MLPromise*) getPromise:(MLPromise*) promise;

-(NSDictionary*) getFiletransferState;
-(void) setFiletransferState:(NSDictionary*) state;

@end

NS_ASSUME_NONNULL_END
