//
//  MLMessageSearch.h
//  monalxmpp
//
//  isaCloud: full text search in the messages (FTS5 index of the text of message_history).
//
//  The index is derived data, kept outside of the Monal ladder of migrations and without triggers: the DataLayer calls
//  -updateIndexForHistoryId:inDatabase: after every change of a message, and -catchUpIndexInDatabase: at every start indexes
//  what the hooks did not see (writes of an older build, a crash between the write and the hook). Writing a message never
//  depends on the index: it is only a lookup table, the result of a search is always checked against message_history.
//
//  Copyright © 2026 isaCloud. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/MLSQLite.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLMessageSearch : NSObject

/// Whether the SQLite of this build has FTS5. A build without it (Xcode reusing an old compiled SQLite, see docs/troubleshooting.md)
/// still works, only the search finds nothing; this is the one place that says so, and it is logged as an error at every start.
+(BOOL) isAvailable;

/// The FTS5 query for what the person typed: every word is a prefix ("lul" finds "lula"), all words must be there, accents and
/// case do not matter. Returns nil if there is nothing to look for (empty, or only punctuation).
+(NSString* _Nullable) matchStringForQuery:(NSString*) query;

/// Creates the index table and fills it with every message that can be found. Run in the isaCloud ladder (inside a write transaction).
+(void) createIndexInDatabase:(MLSQLite*) db;

/// Indexes what was written without the hooks hearing about it, and forgets the entries of messages that do not exist anymore
/// (at most once a day). Run at every start (inside a write transaction).
+(void) catchUpIndexInDatabase:(MLSQLite*) db;

/// Makes the index match the current state of this message: indexed if it can be found, removed if not (or if it was deleted).
/// Call it inside the write transaction that changed the message.
+(void) updateIndexForHistoryId:(NSNumber* _Nullable) historyId inDatabase:(MLSQLite*) db;

/// Same as -updateIndexForHistoryId:, for a message that was just inserted (it cannot be in the index yet, so there is nothing to remove first:
/// that makes it about twice as fast, which matters when the server archive is loaded in bulk).
+(void) indexNewMessageWithHistoryId:(NSNumber* _Nullable) historyId inDatabase:(MLSQLite*) db;

/// Removes the messages matching an SQL condition on message_history from the index. Call it BEFORE deleting them.
+(void) removeFromIndexMessagesWhere:(NSString*) condition arguments:(NSArray*) arguments inDatabase:(MLSQLite*) db;

/// The history ids of the messages having every word of the query, newest first. Messages of disabled accounts, retracted messages and
/// the ones that are not text or a link are never found.
+(NSArray<NSNumber*>*) historyIdsMatchingQuery:(NSString*) query limit:(NSUInteger) limit offset:(NSUInteger) offset inDatabase:(MLSQLite*) db;

@end

NS_ASSUME_NONNULL_END
